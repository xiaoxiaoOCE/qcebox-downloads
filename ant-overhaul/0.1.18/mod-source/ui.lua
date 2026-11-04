-- UE4SS UI bridge. The injected API owns ledger, runtime buffs, and native saves.
local M = {}
local WIDGET = "/Game/UI/InGame/TechTree/Improvments.Improvments_C"
local SPEND = "/Script/EotU.EotUGameState:SpendPlayerRoyalJelly"
local CONFIRM = "BndEvt__Button_2_K2Node_ComponentBoundEvent_8_OnButtonReleasedEvent__DelegateSignature"
local CANCEL = "BndEvt__CancelButton_K2Node_ComponentBoundEvent_10_OnButtonReleasedEvent__DelegateSignature"
local SHOW_DIALOG = "/Game/UI/InGame/TechTree/SpeciesEntry.SpeciesEntry_C:ShowDialog"
local INT_MAX = 2147483647

function M.install(api)
    for _, name in ipairs({ "valid_object", "resolve", "options", "points", "total", "next_cost", "balance", "plan",
        "queue_commit", "queue_native_refresh", "poll_completion", "error" }) do
        assert(type(api[name]) == "function", "missing UI API: " .. name)
    end
    local controller = { last_failure = nil }
    local active, last_original, enabled, blocked = nil, nil, true, false
    local queued, polling_job = nil, false
    local registered, reported = {}, {}
    local clock = api.clock or os.clock
    local hooks_ready, next_hook_retry, discovery_requested = false, 0, true
    local prices, native_payments, native_completions = {}, {}, {}
    local ensure_hooks, refresh_cost, finish_close, retire, guard_session
    -- Only this preallocated numeric mailbox is shared with the main_lua key
    -- callbacks. No UObject, closure, C call or metatable crosses that boundary.
    local INPUT_CAPACITY = 32
    local input_ring, input_drain = {}, {}
    for i = 1, INPUT_CAPACITY do input_ring[i], input_drain[i] = { 0, 0, 0 }, { 0, 0, 0 } end
    local input_head, input_tail, input_seq, input_epoch, input_overflow = 0, 0, 0, 0, 0
    local input_original, input_original_id, input_world_id, input_loop
    local function reset_input_target()
        input_epoch = input_epoch + 1
        input_original, input_original_id, input_world_id = nil, nil, nil
    end
    local function enqueue_key(code)
        if not enabled then return end
        input_seq = input_seq + 1
        if input_tail - input_head >= INPUT_CAPACITY then input_overflow = input_overflow + 1; return end
        local cell = input_ring[input_tail % INPUT_CAPACITY + 1]
        cell[1], cell[2], cell[3] = code, input_epoch, input_seq
        input_tail = input_tail + 1
    end

    local function report(message)
        local ok = pcall(api.error, "[AllAttributes UI] " .. tostring(message))
        if not ok then pcall(print, "[AllAttributes UI] error reporter failed") end
    end
    local function once(key, message)
        if not reported[key] then reported[key] = true; report(message) end
    end
    local function unwrap(value)
        if value == nil then return nil end
        local ok, unwrapped = pcall(function() return value:get() end)
        if ok then return unwrapped end
        return value
    end
    local function valid(value)
        if value == nil then return false end
        local ok, result = pcall(api.valid_object, value)
        return ok and result == true
    end
    local function identity(value)
        if not valid(value) then return nil end
        local ok, result = pcall(function() return value:GetAddress() end)
        if ok then return tostring(result) end
        ok, result = pcall(function() return value:GetFullName() end)
        return ok and result or nil
    end
    local function same(left, right)
        local a, b = identity(left), identity(right)
        return a ~= nil and a == b
    end
    local function in_world(object, world)
        if not valid(object) or not valid(world) then return false end
        local ok, current = pcall(function() return object:GetWorld() end)
        if ok and valid(current) then return same(current, world) end
        -- UGTileGrid is a UObject; some bindings only expose its outer chain.
        current = object
        for _ = 1, 8 do
            ok, current = pcall(function() return current:GetOuter() end)
            if not ok or not valid(current) then return false end
            if same(current, world) then return true end
        end
        return false
    end
    local function displayed(widget, ignore_self_visibility)
        local current = widget
        for index = 1, 32 do
            if not valid(current) then return false end
            local ok, visible = pcall(function() return current:IsVisible() end)
            if not (index == 1 and ignore_self_visibility) and ok and not visible then return false end
            local view, in_view = pcall(function() return current:IsInViewport() end)
            if view and in_view then return true end
            local has_parent, parent = pcall(function() return current:GetParent() end)
            if has_parent and valid(parent) then current = parent
            else
                local has_outer, outer = pcall(function() return current:GetOuter() end)
                if not has_outer or not valid(outer) or same(outer, current) then return false end
                current = outer
            end
        end
        return false
    end
    -- IsValid must precede property lookups: pcall cannot contain a native AV.
    local function context_alive(session)
        local ctx = session.ctx
        if not valid(session.world) or not valid(session.game_state) or not valid(session.grid)
            or not same(ctx.game_state, session.game_state) or not same(ctx.grid, session.grid) then return false end
        for _, name in ipairs({ "game_mode", "player_state" }) do
            if ctx[name] ~= nil and not valid(ctx[name]) then return false end
        end
        return in_world(session.game_state, session.world) and in_world(session.grid, session.world)
            and unwrap(session.grid.ColonyID) == session.colony
    end
    local function payment_context(session, allow_detached)
        if not context_alive(session) or not valid(session.widget)
            or not in_world(session.widget, session.world) then return false end
        -- Only the native dialog itself is deliberately hidden by our clone.
        -- Its owning HUD/TechTree must remain attached and visible throughout.
        if session.original and (not valid(session.original) or not in_world(session.original, session.world)
            or not displayed(session.original, true)) then return false end
        if session.external then
            -- A native Biology root anchors supplemental-only species. Unlike
            -- an original improvements dialog this root is never hidden, and
            -- a stale UObject Outer must not keep a removed screen alive.
            local ok, mounted = pcall(function() return session.original:IsInViewport() end)
            if not (ok and mounted) then
                local good, parent = pcall(function() return session.original:GetParent() end)
                if not good or not valid(parent) then return false end
            end
            if not displayed(session.original) then return false end
        end
        if not allow_detached and not displayed(session.widget) then return false end
        return same(session.widget.OwningTileGrid, session.grid)
    end
    local function is_supplement(widget)
        return active ~= nil and same(widget, active.widget)
    end
    local function integer(value)
        return type(value) == "number" and value == value and value % 1 == 0 and value >= 0 and value <= INT_MAX
    end
    local function text(value)
        local library = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        assert(valid(library), "KismetTextLibrary unavailable")
        return library:Conv_StringToText(tostring(value))
    end
    local function warning(widget, message)
        if valid(widget) then
            local ok = pcall(function()
                local label = widget.WarningText
                if valid(label) then label:SetText(text(message)) end
            end)
            if not ok then once("warning-text", "Unable to display the improvements warning text") end
        end
    end
    local function safe(label, callback)
        return function(...)
            if not enabled then return end
            local ok, err = pcall(callback, ...)
            if not ok then report(label .. ": " .. tostring(err)) end
            -- Always leave the original UFunction return value unchanged.
        end
    end
    local function changes(widget, allow_detached)
        assert(valid(widget), "invalid improvements widget")
        if active and same(widget, active.widget) then
            assert(payment_context(active, allow_detached), "inactive improvements session")
        end
        local rows, count = {}, 0
        for i = 1, 4 do
            local value = unwrap(widget["Value" .. i .. "Change"])
            assert(integer(value), "invalid pending row " .. i)
            rows[i], count = value, count + value
        end
        local spend = unwrap(widget.JellySpend)
        assert(integer(spend) and count <= INT_MAX, "invalid pending total")
        return rows, count, spend
    end
    local function pending_map(session, allow_detached)
        assert(payment_context(session, allow_detached), "inactive improvements session")
        local rows, count, spend = changes(session.widget, allow_detached)
        local result = {}
        for i = 1, 4 do
            local option = session.visible[i]
            if rows[i] > 0 then
                assert(option ~= nil, "pending points in an unused row")
                result[option.id] = rows[i]
            end
        end
        return result, rows, count, spend
    end
    local function pending_equal(a, b)
        for k, v in pairs(a) do if b[k] ~= v then return false end end
        for k, v in pairs(b) do if a[k] ~= v then return false end end
        return true
    end
    local function has_selection(widget)
        local _, count, spend = changes(widget)
        return count > 0 or spend > 0
    end
    local function resolve(widget, read_only)
        if is_supplement(widget) then
            if guard_session(active, false, "price_session_expired") then return active.ctx end
            return nil, "expired_session"
        end
        if not valid(widget) then return nil, "invalid_widget" end
        if read_only and type(api.resolve_view) == "function" then return api.resolve_view(widget) end
        return api.resolve(widget)
    end

    local function set_price_ready(widget, ready, cost)
        if not valid(widget) then return end
        prices[identity(widget)] = ready
        if valid(widget.NextCostNo) then widget.NextCostNo:SetText(text(ready and tostring(cost) or "暂不可用")) end
        for i = 1, 4 do
            local button = widget["Value" .. i .. "Plus"]
            if valid(button) then button:SetIsEnabled(ready) end
        end
        if valid(widget.PurchaseButton) then widget.PurchaseButton:SetIsEnabled(ready) end
    end
    local function unavailable(widget, reason)
        if not valid(widget) then return end
        widget.NextUpgradeCost, widget.PrevUpgradeCost = 0, 0
        set_price_ready(widget, false)
        warning(widget, "加点记录暂不可用；本次不能购买，请取消返回。")
        once("resolve:" .. tostring(reason), "Price context unavailable: " .. tostring(reason))
    end
    refresh_cost = function(widget)
        if not valid(widget) then return end
        if active and active.external and same(widget, active.original) then return end
        if queued then set_price_ready(widget, false); warning(widget, "正在保存本次加点，请稍候。") return end
        if is_supplement(widget) and not guard_session(active, false, "price_session_expired") then return end
        if blocked then unavailable(widget,"unresolved_payment_recovery");return end
        local ctx, err = resolve(widget, true)
        if not ctx then
            unavailable(widget, err)
            return
        end
        local _, pending = changes(widget)
        local total, total_error = api.total(ctx)
        if not integer(total) or total + pending > INT_MAX then unavailable(widget, total_error or "point_overflow"); return end
        total = total + pending
        local cost, cost_error = api.next_cost(total)
        if not integer(cost) or cost <= 0 then
            unavailable(widget, cost_error)
            return
        end
        local previous = 0
        if total > 0 then
            previous = api.next_cost(total - 1)
            assert(integer(previous), "invalid previous upgrade price")
        end
        widget.NextUpgradeCost, widget.PrevUpgradeCost = cost, previous
        set_price_ready(widget, true, cost)
    end

    local function restore_original(session, message)
        local widget = session.original
        if not context_alive(session) or not valid(widget) or not in_world(widget, session.world)
            or not displayed(widget, true) then return end
        if session.external then
            -- Biology has no native small-improvement fields or price methods.
            -- The original screen remains visible behind the modal throughout.
            last_original = nil
            return
        end
        pcall(function() widget:SetVisibility(session.original_visibility or 0) end)
        pcall(function() widget:CalcNextUpgradeCost() end)
        pcall(function() if valid(widget) and valid(widget.ControllerFocus1) then widget.ControllerFocus1:SetFocus() end end)
        if message then warning(widget, message) end
        last_original = widget
    end
    finish_close = function(session, message)
        if active ~= session then return end
        if session.payment and (session.payment.phase == "committed" or session.payment.phase == "rolled_back") then
            input_epoch = input_epoch + 1
        end
        session.terminal = true
        active = nil
        if valid(session.widget) and in_world(session.widget, session.world) and displayed(session.widget) then
            pcall(function() session.widget:RemoveFromParent() end)
        end
        restore_original(session, message)
    end
    -- Only primitive Lua data crosses the session lifetime boundary. Never retain
    -- a widget, ctx, UObject, or a native struct in a recovery record.
    local function primitive_copy(value, seen)
        local kind = type(value)
        if kind == "string" or kind == "boolean" then return value end
        if kind == "number" then return value == value and math.abs(value) < math.huge and value or nil end
        if kind ~= "table" or getmetatable(value) ~= nil then return nil end
        seen = seen or {}
        if seen[value] then return nil end
        seen[value] = true
        local out = {}
        for key, item in pairs(value) do
            if type(key) == "string" or type(key) == "number" then out[key] = primitive_copy(item, seen) end
        end
        seen[value] = nil
        return out
    end
    local function needs_recovery(payment)
        return payment and payment.phase ~= "committed" and payment.phase ~= "rolled_back"
            and ((payment.before ~= nil and payment.after ~= nil and payment.before ~= payment.after)
                or payment.plan ~= nil or payment.phase == "paying" or payment.phase == "native_verification_failed"
                or payment.zeroed == false)
    end
    local function preserve_receipt(session, payment, reason, quiet)
        blocked = true
        local record = primitive_copy(session.evidence) or {}
        for _, key in ipairs({ "before", "after", "cost", "amount", "spend", "colony", "phase", "zeroed", "basket_cleared", "rows", "pending", "plan" }) do
            record[key] = primitive_copy(payment[key])
        end
        record.reason = tostring(reason)
        -- Preserve older unresolved evidence if additional terminal hooks arrive.
        if not controller.last_failure then controller.last_failure = record end
        if not quiet then
            report("Payment recovery required: slot=" .. tostring(record.slot) .. " group=" .. tostring(record.group)
                .. " before=" .. tostring(record.before) .. " cost=" .. tostring(record.cost or record.amount)
                .. " reason=" .. record.reason)
        end
        return controller.last_failure
    end
    local function queue_failure(job, reason)
        job.phase, job.reason, job.faulted = "recovery_required", tostring(reason), true
        blocked = true
        local record = primitive_copy(job)
        for key, value in pairs(job.evidence or {}) do if record[key] == nil then record[key] = value end end
        controller.last_failure = controller.last_failure or record
        if job.kind == "native" then controller.last_native_completion_error = record end
        report("加点收尾需要恢复，已保留付款记录：" .. job.reason)
    end
    local function queued_notice()
        report("本次加点正在保存并刷新单位，请稍候；暂不能翻页、取消或准备卸载。")
        return nil, "transaction_in_progress"
    end
    local function accept_job(job, called, id, err)
        if called and ((type(id) == "number" and integer(id) and id > 0) or (type(id) == "string" and id ~= "")) then
            job.job_id, job.phase = id, "queued"
        else queue_failure(job, called and (err or "queue_refused") or id) end
        -- All surviving state is primitive. The native graph may already have
        -- removed/destroyed its widget; never carry that wrapper into a frame.
        active, last_original = nil, nil
        reset_input_target()
    end
    retire = function(session, reason, attempt_refund)
        if active ~= session or session.terminal then return true end
        if reason ~= "close_during_payment" then reset_input_target() end
        local payment = session.payment
        local previous_failure, previous_block = controller.last_failure, blocked
        -- Detach only after the receipt is safe: even lifetime checks or cleanup
        -- may throw, and a failed RemoveFromParent must never erase the debit.
        local protected = needs_recovery(payment) and preserve_receipt(session, payment, reason, true) or nil
        session.terminal = true
        active, last_original = nil, nil
        local recovered = false
        if needs_recovery(payment) and attempt_refund and payment.phase ~= "committing"
            and integer(payment.before) and integer(payment.cost) and payment.cost > 0
            and type(api.refund_native) == "function" and context_alive(session) then
            local called, restored = pcall(api.refund_native, session.ctx, session.colony, payment.before, payment.cost)
            recovered = called and restored == true
            if recovered then
                payment.phase, payment.valid = "rolled_back", false
                if not previous_failure and controller.last_failure == protected then
                    controller.last_failure, blocked = nil, previous_block
                end
            end
        end
        if needs_recovery(payment) then
            preserve_receipt(session, payment, reason)
        end
        if attempt_refund then
            local cleaned, cleanup_error = pcall(function()
                if context_alive(session) and valid(session.widget) and in_world(session.widget, session.world)
                    and displayed(session.widget) then session.widget:RemoveFromParent() end
            end)
            if not cleaned then report("Window removal failed; payment evidence retained: " .. tostring(cleanup_error)) end
            local restored, restore_error = pcall(restore_original, session,
                recovered and "本次额外加点已取消，蜂王浆已全额退还。"
                or (blocked and "本次付款需要恢复，已停止后续加点。请保留日志，不要重复确认。" or nil))
            if not restored then report("Original window restore failed: " .. tostring(restore_error)) end
        end
        if needs_recovery(payment) then return nil, "recovery_required" end
        if recovered then report("Expired UI transaction refunded exactly; no extra point was committed") end
        return true
    end
    guard_session = function(session, allow_detached, reason)
        if active ~= session or session.terminal then return false end
        if payment_context(session, allow_detached) then return true end
        retire(session, reason or "session_lifetime_ended", true)
        return false
    end
    local function transaction_failure(session, reason, payment)
        local details = payment or session.payment
        if needs_recovery(details) then
            preserve_receipt(session, details, reason)
        else report("Purchase refused: " .. tostring(reason)) end
        finish_close(session, "本次额外加点未完成；请查看模组提示，勿重复确认。")
    end

    local function render_page(session, index)
        assert(guard_session(session, false, "page_session_expired"), "inactive improvements session")
        assert(not has_selection(session.widget), "cancel or confirm pending points before changing page")
        session.page, session.visible = index, {}
        local pages = math.ceil(#session.options / 4)
        local widget = session.widget
        -- Pages belong to one selected unit group. Keep its original native
        -- portrait instead of the newly created widget's default worker icon.
        assert(valid(widget.AntImage) and valid(session.icon), "unit portrait expired")
        widget.AntImage:SetBrushFromTexture(session.icon, false)
        widget.Title:SetText(text(session.group_title .. " · 额外属性"))
        widget.ScientificName:SetText(text(string.format("第 %d/%d 页 · F6翻页\nF7返回 · F8准备卸载", index, pages)))
        for i = 1, 4 do
            local option = session.options[(index - 1) * 4 + i]
            session.visible[i] = option
            widget["Value" .. i .. "Change"] = 0
            -- Rows 1/2 exist in the widget tree but are not exposed variables.
            -- Their title's parent is the row HorizontalBox, then its Overlay.
            local row_root = i >= 3 and widget["Val" .. i .. "Overlay"]
                or widget["Value" .. i .. "Title"]:GetParent():GetParent()
            assert(valid(row_root), "row container unavailable: " .. i)
            row_root:SetVisibility(option and 0 or 1)
            if i >= 3 then widget["Value" .. i .. "Row"] = option ~= nil end
            if option then
                widget["Value" .. i .. "Title"]:SetText(text(option.title))
                local description = option.description or option.title
                if not description:find("{Arg1}", 1, true) then description = description .. "（额外提升 {Arg1}；每点 {Arg2}）" end
                widget["Value" .. i .. "Text"] = text(description)
                widget["Value" .. i .. "Increment"] = option.per_point
            end
        end
        widget.JellySpend = 0
        session.accepted = { rows = { 0, 0, 0, 0 }, spend = 0 }
        warning(widget, "")
        refresh_cost(widget)
        pcall(function() widget.ControllerFocus1:SetFocus() end)
    end
    local function visible_original(widget)
        if not valid(widget) or is_supplement(widget) then return false end
        return displayed(widget)
    end
    local function find_original(allow_scan)
        if visible_original(last_original) then return last_original end
        if allow_scan == false then return nil end
        for _, widget in ipairs(FindAllOf("Improvments_C") or {}) do
            if visible_original(widget) then return widget end
        end
    end
    local function bind_input_dialog(widget, new_lifecycle)
        if not valid(widget) or is_supplement(widget) then return false end
        local world = widget:GetWorld()
        if not valid(world) or not valid(widget.OwningTileGrid) or not in_world(widget.OwningTileGrid, world) then return false end
        if active and (new_lifecycle or not same(active.original, widget)) then
            retire(active, "native_dialog_replaced", true)
        end
        local widget_id, world_id = identity(widget), identity(world)
        if new_lifecycle or widget_id ~= input_original_id or world_id ~= input_world_id then input_epoch = input_epoch + 1 end
        input_original, input_original_id, input_world_id = widget, widget_id, world_id
        last_original = widget
        return true
    end
    local function open(original, external_ctx, external_icon)
        if queued then return queued_notice() end
        if active then guard_session(active, false, "open_session_expired") end
        if blocked then report("A previous purchase needs recovery before another extra purchase can start"); return nil, "recovery_required" end
        if active then return nil, "already_open" end
        ensure_hooks(true)
        for _, name in ipairs({ "GetValueByNo", "CalcNextUpgradeCost", "PurchaseEvent", CONFIRM, CANCEL,
            "Close Widget", "AttemptSpend", "AttemptRefund", "native_spend" }) do
            if not registered[name] then return nil, "hook_unavailable:" .. name end
        end
        original = original or find_original()
        if not visible_original(original) then report("先打开一个兵种的原版小幅改进窗口，再按 F6。"); return nil, "no_original_widget" end
        if not external_ctx and has_selection(original) then warning(original, "请先确认或用减号撤回原版窗口中尚未确认的点数。") return nil, "pending_purchase" end
        local ctx, err = external_ctx, nil
        if not ctx then ctx, err = resolve(original, true) end
        if not ctx then warning(original, "无法读取当前兵种的加点记录。") return nil, err end
        local icon = external_icon
        if not external_ctx then
            local original_image = original.AntImage
            if not valid(original_image) then return nil, "original_image_expired" end
            icon = original_image.Brush.ResourceObject
        end
        if not valid(icon) then warning(original, "兵种图标尚未加载，请稍候重试。") return nil, "original_icon_unavailable" end
        assert(ctx.group and type(ctx.group.title) == "string", "unit group title unavailable")
        assert(valid(ctx.grid) and valid(ctx.game_state), "invalid game context")
        local world = ctx.game_state:GetWorld()
        assert(valid(world) and in_world(ctx.grid, world), "invalid or mismatched game world")
        local options, options_error = api.options(ctx)
        if type(options) ~= "table" or #options == 0 then warning(original, "这个兵种目前没有可追加的属性。") return nil, options_error or "no_options" end
        local seen = {}
        for _, option in ipairs(options) do
            assert(type(option) == "table" and type(option.id) == "string" and not seen[option.id]
                and type(option.title) == "string" and type(option.per_point) == "number"
                and option.per_point == option.per_point and math.abs(option.per_point) < math.huge, "invalid option")
            seen[option.id] = true
        end
        local owner = original:GetOwningPlayer()
        local creator = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local class = StaticFindObject(WIDGET)
        assert(valid(owner) and valid(creator) and valid(class), "widget dependencies unavailable")
        local widget = creator:Create(owner, class, owner)
        assert(valid(widget), "supplemental widget creation failed")
        widget.OwningTileGrid, widget.Species, widget.CreatureName = ctx.grid, 255, FName("CodexExtra")
        local session = { widget = widget, original = original, ctx = ctx, options = options, visible = {}, page = 1,
            external = external_ctx ~= nil,
            icon = icon, group_title = ctx.group.title,
            world = world, game_state = ctx.game_state, grid = ctx.grid, colony = unwrap(ctx.grid.ColonyID),
            original_visibility = original:GetVisibility(), accepted = { rows = { 0, 0, 0, 0 }, spend = 0 } }
        session.evidence = { kind = "supplemental", slot = ctx.slot, group = ctx.group.id,
            world = identity(world), game_state = identity(ctx.game_state), grid = identity(ctx.grid),
            widget = identity(widget), colony = session.colony }
        active = session
        local ok, create_error = pcall(function()
            for i = 1, 4 do widget["Value" .. i .. "Change"] = 0 end
            widget.JellySpend = 0
            widget:AddToViewport(1000)
            render_page(session, 1)
            if not session.external then original:SetVisibility(1) end
        end)
        if not ok then finish_close(session); error(create_error) end
        return true
    end

    local function validate_pending(context, value_change, success)
        local widget = unwrap(context)
        if not is_supplement(widget) then return end
        local session = active
        if not guard_session(session, false, "pending_session_expired") then return end
        local pending, rows, count, spend = pending_map(session)
        local ok, err = true, nil
        if count == 0 then ok = spend == 0; err = "empty_selection_cost_mismatch"
        else
            local plan
            plan, err = api.plan(session.ctx, pending)
            ok = plan ~= nil and plan.cost == spend
            if plan and not ok then err = "pending_cost_mismatch" end
        end
        if ok then session.accepted = { rows = rows, spend = spend }; return end
        local changed
        for i = 1, 4 do
            if rows[i] ~= session.accepted.rows[i] then changed = changed or i end
            widget["Value" .. i .. "Change"] = session.accepted.rows[i]
        end
        widget.JellySpend = session.accepted.spend
        if changed and value_change then pcall(function() value_change:set(session.accepted.rows[changed]) end) end
        if success then pcall(function() success:set(false) end) end
        refresh_cost(widget)
        warning(widget, "不能继续增加：资金不足、达到属性上限，或加点记录暂不可用。")
        once("pending:" .. tostring(err), "Pending allocation refused: " .. tostring(err))
    end

    local function spend_pre(context, colony, jelly)
        local session = active
        if session and not payment_context(session, false) then
            local belongs = same(unwrap(context), session.game_state) and unwrap(colony) == session.colony
                and unwrap(jelly) == (session.payment and session.payment.cost or session.accepted.spend)
            retire(session, "payment_session_expired", true)
            if belongs then jelly:set(0); return end
            session = nil
        end
        if not session then
            local widget = find_original()
            if not widget then return end
            local amount = unwrap(jelly)
            local gs = unwrap(context)
            -- A modal improvements confirmation passes this widget's reserved
            -- basket. Leave unrelated colony / unlock spending alone.
            local scoped, belongs = pcall(function()
                return valid(widget.OwningTileGrid) and unwrap(colony) == unwrap(widget.OwningTileGrid.ColonyID)
                    and in_world(gs, widget:GetWorld()) and amount == unwrap(widget.JellySpend)
            end)
            if scoped and not belongs then return end
            jelly:set(0) -- Protect the native call before any fallible API work.
            local ok, payment = pcall(function()
                assert(not queued, "completion_already_pending")
                assert(not blocked,"unresolved_payment_recovery")
                assert(prices[identity(widget)] ~= false, "price_not_ready")
                local ctx, err = resolve(widget); assert(ctx, err)
                assert(same(ctx.game_state, gs) and same(ctx.grid, widget.OwningTileGrid), "native_context_changed")
                local rows, quantity, spend = changes(widget)
                local total = api.total(ctx)
                assert(integer(total) and quantity > 0 and total + quantity <= INT_MAX, "point_overflow")
                local expected = api.cost_for and api.cost_for(total, quantity)
                local before = api.balance(ctx)
                assert(integer(expected) and expected > 0 and expected == spend and amount == expected
                    and integer(before) and before >= expected, "native_quote_or_balance_mismatch")
                assert(not native_payments[identity(gs)] and not native_completions[identity(widget)], "overlapping_native_purchase")
                local world = gs:GetWorld()
                assert(valid(world) and in_world(ctx.grid, world), "native_world_changed")
                local lifecycle = { widget = widget, ctx = ctx, game_state = gs, grid = ctx.grid, world = world,
                    colony = unwrap(colony), evidence = { kind = "native", slot = ctx.slot, group = ctx.group.id,
                        world = identity(world), game_state = identity(gs), grid = identity(ctx.grid), widget = identity(widget) } }
                assert(payment_context(lifecycle, false), "native_widget_expired")
                return { widget = widget, ctx = ctx, lifecycle = lifecycle, before = before, amount = amount,
                    colony = unwrap(colony), rows = rows, spend = spend, total_before = total, quantity = quantity, phase = "paying" }
            end)
            if not ok then
                if valid(widget) and displayed(widget) then
                    for i = 1, 4 do widget["Value" .. i .. "Change"] = 0 end
                    widget.JellySpend = 0
                    unavailable(widget, payment)
                end
                return
            end
            native_payments[identity(gs)] = payment
            jelly:set(amount)
            return
        end
        if not same(unwrap(context), session.game_state) then return end
        local colony_id, amount = unwrap(colony), unwrap(jelly)
        if colony_id ~= session.colony then return end
        local observed_before
        if context_alive(session) then pcall(function() observed_before = api.balance(session.ctx) end) end
        local ok, err = pcall(function()
            assert(payment_context(session), "payment world or colony changed")
            assert(unwrap(session.widget.Species) == 255, "supplemental sentinel changed")
            local pending, _, count, reserved = pending_map(session)
            assert(not session.payment, "duplicate or overlapping payment")
            assert(count > 0 and integer(amount) and amount == reserved, "native payment does not match selection")
            local plan, plan_error = api.plan(session.ctx, pending)
            assert(plan and plan.cost > 0 and plan.cost == amount, "plan refused or price changed: " .. tostring(plan_error))
            local before = api.balance(session.ctx)
            assert(integer(before) and before == plan.balance and before >= amount, "balance changed before payment")
            session.payment = { plan = plan, pending = pending, before = before, cost = amount, colony = colony_id, phase = "paying" }
        end)
        if not ok then
            local zeroed, zero_error = pcall(function() jelly:set(0) end)
            if session.payment then
                -- Keep the first debit's evidence even if a second call is suppressed.
                session.payment.phase, session.payment.valid = "payment_mismatch", false
                session.payment.reason, session.payment.zeroed = tostring(err), zeroed
            else
                session.payment = { phase = "rejected", reason = tostring(err), zeroed = zeroed,
                    before = observed_before, colony = colony_id }
            end
            if payment_context(session, false) then warning(session.widget, "本次购买已拒绝，未记录额外点数。") end
            report("Payment precheck rejected: " .. tostring(err))
            if not zeroed then report("Unable to suppress native payment; recovery may be required: " .. tostring(zero_error)) end
        end
    end
    -- UE4SS 3.0.1-1183 inserts the native return slot before function arguments.
    local function spend_post(context, return_value, colony, jelly)
        local session = active
        if not session then
            local key = identity(unwrap(context))
            local payment = native_payments[key]
            if not payment or payment.phase ~= "paying" then return end
            -- Keep the receipt while verifying. Reentrant posts see this phase;
            -- exceptions cannot silently consume a debit before it is recorded.
            payment.phase, payment.basket_cleared = "verifying", false
            local processed, failure = pcall(function()
                assert(payment_context(payment.lifecycle, true), "native_session_expired")
                -- Stock code applies ranks unconditionally after this native call.
                -- Never refund unless every pending field was cleared and read back.
                for i = 1, 4 do payment.widget["Value" .. i .. "Change"] = 0 end
                payment.widget.JellySpend = 0
                local _, count, spend = changes(payment.widget, true)
                assert(count == 0 and spend == 0, "native_basket_clear_not_verified")
                payment.basket_cleared = true
                local ok, after = pcall(api.balance, payment.ctx)
                payment.after = ok and after or nil
                if ok and unwrap(colony) == payment.colony and unwrap(jelly) == payment.amount
                    and after == payment.before - payment.amount then
                    assert(payment_context(payment.lifecycle, true), "native_session_expired")
                    for i = 1, 4 do payment.widget["Value" .. i .. "Change"] = payment.rows[i] end
                    payment.widget.JellySpend = payment.spend
                    local rows, _, restored_spend = changes(payment.widget, true)
                    assert(pending_equal(rows, payment.rows) and restored_spend == payment.spend, "native_basket_restore_not_verified")
                    -- This is only a paid-basket receipt. The stock blueprint
                    -- writes its ranks after SpendPlayerRoyalJelly returns.
                    native_completions[identity(payment.widget)] = {
                        evidence = primitive_copy(payment.lifecycle.evidence), colony = payment.colony,
                        expected_total = payment.total_before + payment.quantity,
                        before = payment.before, after = payment.after, phase = "awaiting_completion"
                    }
                    payment.phase = "committed"
                    native_payments[key] = nil
                    return
                end
                payment.phase = "native_verification_failed"
                assert(context_alive(payment.lifecycle), "native_recovery_context_expired")
                local called, restored, reason = pcall(function()
                    assert(type(api.refund_native) == "function", "native recovery unavailable")
                    return api.refund_native(payment.ctx, payment.colony, payment.before, payment.amount)
                end)
                assert(called and restored == true, tostring(reason or restored))
                payment.phase = "rolled_back"
                native_payments[key] = nil
                if payment_context(payment.lifecycle, true) then
                    unavailable(payment.widget, "native_payment_rolled_back")
                    warning(payment.widget, "本次购买未完成，蜂王浆未损失。请取消后重新打开。")
                end
            end)
            if not processed and payment.phase ~= "committed" and payment.phase ~= "rolled_back" then
                payment.phase = "native_verification_failed"
                local receipt = preserve_receipt(payment.lifecycle, payment, failure)
                -- A blocked tombstone holds only primitive evidence, not stale UE
                -- references. A later post must neither refund nor restore rows.
                native_payments[key] = { phase = "recovery_required", recovery = receipt }
                local cleaned, cleanup_error = pcall(function()
                    if payment_context(payment.lifecycle, true) then
                        unavailable(payment.widget, "native_payment_recovery_required")
                        warning(payment.widget, "本次付款未能核验，已停止加点。请保留日志，不要重复确认。")
                    end
                end)
                if not cleaned then report("Recovery warning failed; receipt retained: " .. tostring(cleanup_error)) end
            elseif not processed then
                report("Native transaction completed; UI cleanup failed: " .. tostring(failure))
            end
            return
        end
        if not same(unwrap(context), session.game_state) then return end
        local payment = session.payment
        if not payment then return end
        if unwrap(colony) ~= payment.colony then return end
        if not guard_session(session, true, "payment_post_session_expired") then return end
        if payment.phase == "rejected" then
            payment.after = api.balance(session.ctx)
            return
        end
        if payment.phase ~= "paying" then return end
        local after = api.balance(session.ctx)
        payment.after = after
        -- SpendPlayerRoyalJelly is void: the return slot is not a success receipt.
        payment.valid = payment_context(session, true) and unwrap(jelly) == payment.cost
            and payment.plan.cost == payment.cost and payment.plan.balance == payment.before
            and integer(after) and after == payment.before - payment.cost
        payment.phase = payment.valid and "paid" or "payment_mismatch"
    end
    local function native_purchase_finished(widget)
        local key = identity(widget)
        local receipt = key and native_completions[key]
        if not receipt then return end
        -- Consume before calling any API: nested controller/mouse completion
        -- paths must not refresh a completed purchase a second time.
        native_completions[key] = nil
        local ok, err = pcall(function()
            assert(valid(widget), "native_completion_widget_expired")
            local frozen = receipt.evidence
            local ctx, why = api.resolve(widget); assert(ctx, why)
            assert(valid(ctx.game_state) and valid(ctx.grid), "native_completion_context_expired")
            local world = ctx.game_state:GetWorld()
            assert(identity(world) == frozen.world and identity(ctx.game_state) == frozen.game_state
                and identity(ctx.grid) == frozen.grid and ctx.slot == frozen.slot
                and ctx.group and ctx.group.id == frozen.group and in_world(widget, world)
                and in_world(ctx.grid, world) and same(widget.OwningTileGrid, ctx.grid)
                and unwrap(ctx.grid.ColonyID) == receipt.colony, "native_completion_context_changed")
            assert(api.total(ctx) == receipt.expected_total, "native_ranks_not_committed")
            assert(not queued, "completion_already_pending")
            local job = primitive_copy(receipt)
            job.kind, job.phase, job.original_id = "native", "reserving", key
            queued = job
            local called, id, reason = pcall(api.queue_native_refresh, ctx, primitive_copy(receipt))
            accept_job(job, called, id, reason)
        end)
        if not ok then
            receipt.phase, receipt.reason = "completion_refresh_failed", tostring(err)
            controller.last_native_completion_error = receipt -- primitive evidence only
            blocked = true
            controller.last_failure = controller.last_failure or primitive_copy(receipt)
            report("原版加点完成后的单位刷新未完成：" .. tostring(err) .. "；未退款或撤销原版点数。")
            if valid(widget) then warning(widget, "原版加点后的单位刷新未完成，请查看模组日志。") end
        end
    end
    local function purchase_finished(context)
        local widget = unwrap(context)
        if not is_supplement(widget) then
            local key = identity(widget)
            if key and key == input_original_id then input_epoch = input_epoch + 1 end
            native_purchase_finished(widget)
            return
        end
        local session, payment = active, active.payment
        -- Both the mouse event and PurchaseEvent may unwind through this hook.
        if session.completing or session.terminal then return end
        if not guard_session(session, true, "purchase_completion_session_expired") then return end
        session.completing = true
        if not payment or not payment.valid or payment.phase ~= "paid" then
            transaction_failure(session, payment and (payment.reason or payment.phase) or "missing_payment_receipt", payment)
            return
        end
        local pending = pending_map(session, true)
        if not pending_equal(pending, payment.pending) then transaction_failure(session, "selection_changed_after_payment", payment); return end
        if not payment_context(session, true) or api.balance(session.ctx) ~= payment.after
            or payment.plan.cost ~= payment.cost or payment.plan.balance ~= payment.before then
            transaction_failure(session, "payment_context_or_balance_changed", payment); return
        end
        if queued then transaction_failure(session, "completion_already_pending", payment); return end
        local job = primitive_copy(payment)
        job.kind, job.phase, job.evidence = "extra", "reserving", primitive_copy(session.evidence)
        job.original_id, job.original_visibility = identity(session.original), session.original_visibility
        job.external = session.external == true
        queued = job -- Gate reentrant hooks before any fallible API work.
        payment.phase, session.terminal = "queued", true
        local called, id, err = pcall(api.queue_commit, session.ctx, payment.plan, payment.before, payment.after)
        accept_job(job, called, id, err)
    end
    local function cancel_finished(context)
        local widget = unwrap(context)
        if not is_supplement(widget) then
            local key = identity(widget)
            if key and key == input_original_id then reset_input_target() end
            return
        end
        if not is_supplement(widget) then return end
        local session = active
        if session.completing or session.terminal then return end
        if session.payment then retire(session, "window_closed_during_payment", true); return end
        finish_close(session, "已取消尚未确认的额外加点，蜂王浆未扣除。")
    end
    local function confirm_finished(context)
        local session = active
        local ok, err = pcall(purchase_finished, context)
        if not ok and session and active == session then
            transaction_failure(session, "purchase completion exception: " .. tostring(err))
        elseif not ok then report("Purchase completion: " .. tostring(err)) end
    end

    local callbacks = {
        Setup = function(context)
            local widget = unwrap(context)
            if valid(widget) and not is_supplement(widget) then
                -- Setup can precede AddChildToOverlay. Bind its new epoch now;
                -- consumption still requires the eventual real displayed tree.
                bind_input_dialog(widget, true)
                last_original = widget; refresh_cost(widget)
            end
        end,
        CanAfford = function(context, output)
            local widget = unwrap(context)
            if valid(widget) and prices[identity(widget)] == false then output:set(false) end
        end,
        GetValueByNo = function(context, no, output)
            local widget = unwrap(context)
            if not is_supplement(widget) then return end
            if not guard_session(active, true, "value_session_expired") then return end
            local index = unwrap(no)
            assert(integer(index) and index >= 1 and index <= 4, "invalid requested row")
            local option = active.visible[index]
            local value = option and api.points(active.ctx, option.id) or 0
            assert(integer(value), "invalid ledger rank")
            output:set(value)
        end,
        CalcNextUpgradeCost = function(context)
            local widget = unwrap(context)
            if valid(widget) then refresh_cost(widget) end
        end,
        AttemptSpend = validate_pending,
        AttemptRefund = validate_pending,
        PurchaseEvent = confirm_finished,
        [CONFIRM] = confirm_finished,
        ["Close Widget"] = cancel_finished,
        [CANCEL] = cancel_finished
    }
    ensure_hooks = function(immediate)
        if hooks_ready then return true end
        local now = clock()
        if not immediate and now < next_hook_retry then return false end
        next_hook_retry = now + 1
        local discovered = registered.Setup and registered.show_dialog
        if not registered.show_dialog and valid(StaticFindObject(SHOW_DIALOG)) then
            local ok, pre, post = pcall(RegisterHook, SHOW_DIALOG, safe("native ShowDialog", function(context, content)
                local owner, widget = unwrap(context), unwrap(content)
                if not valid(owner) or not valid(widget) or not displayed(widget) then return end
                local class = StaticFindObject(WIDGET)
                if not valid(class) or not widget:IsA(class) or not in_world(owner, widget:GetWorld()) then return end
                -- A real native dialog proves the Blueprint has loaded. Hook
                -- its input/payment functions before the first short F6 press.
                ensure_hooks(true)
                -- Completes the same Setup lifecycle, or discovers a first dialog
                -- whose Setup hook was not loaded yet. Never advance twice.
                if bind_input_dialog(widget, false) then refresh_cost(widget) end
            end))
            if ok and type(pre) == "number" and type(post) == "number" then registered.show_dialog = { SHOW_DIALOG, pre, post } end
        end
        local widget_loaded = valid(StaticFindObject(WIDGET))
        for name, callback in pairs(callbacks) do
            if widget_loaded and not registered[name] then
                local path = WIDGET .. ":" .. name
                if valid(StaticFindObject(path)) then
                    local ok, pre, post = pcall(RegisterHook, path, safe(name, callback))
                    if ok and type(pre) == "number" and type(post) == "number" then registered[name] = { path, pre, post } end
                end
            end
        end
        if not registered.native_spend and valid(StaticFindObject(SPEND)) then
            local ok, pre, post = pcall(RegisterHook, SPEND, spend_pre, safe("native spend post", spend_post))
            if ok and type(pre) == "number" and type(post) == "number" then registered.native_spend = { SPEND, pre, post } end
        end
        hooks_ready = registered.show_dialog ~= nil and registered.native_spend ~= nil
        for name in pairs(callbacks) do
            if not registered[name] then hooks_ready = false; break end
        end
        -- Catch a dialog that was already open when its late-loaded hooks
        -- became available. Missing classes do not cause an idle world scan.
        if not discovered and registered.Setup and registered.show_dialog then discovery_requested = true end
        return hooks_ready
    end

    function controller.open(original) return open(original) end -- Game-thread callers only.
    function controller.open_external(ctx, anchor, icon)
        if type(ctx) ~= "table" or not ctx.group or ctx.group.supplemental ~= true
            or ctx.is_formicarium ~= true then return nil, "invalid_external_group" end
        if not valid(StaticFindObject(WIDGET)) then LoadAsset(WIDGET) end
        return open(anchor, ctx, icon)
    end
    function controller.next_page(expected_original)
        if queued then return queued_notice() end
        if active and active.completing then
            if payment_context(active, true) then warning(active.widget, "交易正在提交，请稍候再按 F6 翻页。") end
            report("交易正在提交，请稍候再按 F6 翻页。")
            return nil, "transaction_in_progress"
        end
        if active then guard_session(active, false, "page_session_expired") end
        if not active then return open(expected_original) end
        if active.payment then
            warning(active.widget, "正在核验付款，请稍候；如需取消可按 F7 核验退款。")
            report("正在核验付款，暂不能翻页。F7 可核验取消。")
            return nil, "transaction_in_progress"
        end
        if has_selection(active.widget) then warning(active.widget, "请先确认加点，或用减号撤回待加点后再翻页。") return nil, "pending_purchase" end
        render_page(active, active.page % math.ceil(#active.options / 4) + 1)
        return true
    end
    function controller.close()
        if queued then return queued_notice() end
        if not active then
            if blocked then report("本次付款需要恢复，已停止后续加点。请保留日志，不要重复确认。"); return nil, "recovery_required" end
            return true
        end
        if active.completing then
            if payment_context(active, true) then warning(active.widget, "交易正在提交并保存，请稍候；此时不能取消。") end
            report("交易正在提交并保存，请稍候；F7 此时不能取消。")
            return nil, "transaction_in_progress"
        end
        if not guard_session(active, false, "close_session_expired") then return not blocked, blocked and "recovery_required" or nil end
        if active.payment then
            warning(active.widget, "正在核验并取消本次付款，请稍候。")
            report("F7：正在核验并取消本次付款。")
            return retire(active, "close_during_payment", true)
        end
        finish_close(active, "已取消尚未确认的额外加点，蜂王浆未扣除。")
        return true
    end
    function controller.validate()
        if active then guard_session(active, active.completing == true, "session_lifetime_ended") end
        return active ~= nil
    end
    function controller.get_active() controller.validate(); return active end -- Game-thread callers only; do not mutate it.
    function controller.get_queued() return queued and primitive_copy(queued) or nil end
    function controller.invalidate(reason, attempt_refund)
        reset_input_target()
        discovery_requested = true
        if queued then
            queued.invalidated, queued.invalidation_reason = true, tostring(reason or "world_invalidated")
            active, last_original, prices = nil, nil, {}
            return nil, "transaction_in_progress"
        end
        local ok, err = true, nil
        if active then ok, err = retire(active, reason or "session_invalidated", attempt_refund == true) end
        for key, payment in pairs(native_payments) do
            if not payment.recovery then preserve_receipt(payment.lifecycle, payment, reason or "native_session_invalidated") end
            native_payments[key] = nil
            ok, err = nil, "recovery_required"
        end
        for key, receipt in pairs(native_completions) do
            receipt.phase, receipt.reason = "completion_not_observed", reason or "world_invalidated"
            controller.last_native_completion_error = receipt
            native_completions[key] = nil
            report("原版购买完成事件未能核验，已保留纯数值记录；未跨世界刷新或退款。")
        end
        last_original, prices = nil, {}
        if blocked then return nil, "recovery_required" end
        return ok, err
    end
    function controller.show_message(message)
        controller.validate()
        local widget = active and active.widget or last_original
        if valid(widget) and displayed(widget) then warning(widget, message) end
    end
    function controller.retry_hooks() ensure_hooks(true); return registered end
    function controller.resume_after_recovery()
        if queued then return queued_notice() end
        blocked, controller.last_failure = false, nil
        for key, payment in pairs(native_payments) do
            if payment.phase == "recovery_required" then native_payments[key] = nil end
        end
    end
    function controller.shutdown()
        if queued then return queued_notice() end
        if blocked then return nil, "recovery_required" end
        local closed, reason = controller.close()
        if not closed then return nil, reason end
        enabled = false
        if input_loop and type(CancelDelayedAction) == "function" then pcall(CancelDelayedAction, input_loop) end
        for _, hook in pairs(registered) do pcall(UnregisterHook, hook[1], hook[2], hook[3]) end
        return true
    end
    local function completion_notice(job, message)
        if job.external then
            report(job.kind == "extra" and "蚁种培养已处理，可在生物适应中再次选择该蚁种。" or message)
            return
        end
        local frozen = job.evidence or {}
        for _, widget in ipairs(FindAllOf("Improvments_C") or {}) do
            if valid(widget) and identity(widget:GetWorld()) == frozen.world then
                local original = identity(widget) == job.original_id
                if displayed(widget, original) then
                    local ok, ctx = pcall(api.resolve, widget)
                    if ok and ctx and ctx.slot == frozen.slot and ctx.group and ctx.group.id == frozen.group then
                        if original and job.kind == "extra" then widget:SetVisibility(job.original_visibility or 0) end
                        if displayed(widget) then
                            last_original = widget
                            refresh_cost(widget)
                            warning(widget, message)
                            return
                        end
                    end
                end
            end
        end
        report(message)
    end
    local function poll_queued()
        local job = queued
        if not job or polling_job then return end
        if job.faulted then
            if not job.notified then
                job.notified = true
                completion_notice(job, "本次加点收尾需要恢复，已保留付款记录；请勿重复购买。")
            end
            return
        end
        if not job.job_id then return end
        polling_job = true
        local ok, result, reason = pcall(api.poll_completion, job.job_id)
        polling_job = false
        if not ok then queue_failure(job, result); return end
        if result == nil and (reason == "pending" or reason == "completion_in_progress") then return end
        if type(result) == "table" and (result.phase == "queued" or result.phase == "running") then return end
        if type(result) ~= "table" or result.kind ~= job.kind
            or (result.phase ~= "committed" and result.phase ~= "rolled_back" and result.phase ~= "recovery_required") then
            queue_failure(job, reason or "invalid_completion_result"); return
        end
        if result.phase == "rolled_back" and (job.kind ~= "extra" or result.balance ~= job.before) then
            queue_failure(job, "unverified_completion_refund"); return
        end
        controller.last_completion = primitive_copy(result)
        controller.last_completion.job_id = job.job_id
        if result.phase == "recovery_required" then queue_failure(job, result.reason or "completion_failed") end
        queued = nil -- A known terminal result is the only normal release.
        input_epoch = input_epoch + 1
        local message = result.phase == "committed"
            and (job.kind == "native" and "原版加点已完成，同兵种单位已刷新。" or "额外属性加点已确认并保存。F6 可继续查看。")
            or (result.phase == "rolled_back" and "本次额外加点未完成，蜂王浆已全额退还。F6 可重新打开。"
                or "本次加点收尾需要恢复，已保留付款记录；请勿重复购买。")
        completion_notice(job, message)
    end
    local function observe_input_target(allow_scan)
        -- Retire stale sessions before a new native dialog can receive input.
        if active then guard_session(active, active.completing == true, "input_session_expired") end
        if active and not valid(active.original) then retire(active, "input_original_expired", true) end
        local original = active and active.original or find_original(allow_scan)
        local world = valid(original) and original:GetWorld() or nil
        local original_id, world_id = identity(original), identity(world)
        if not original_id or not world_id then original, original_id, world_id = nil, nil, nil end
        local changed = original_id ~= input_original_id or world_id ~= input_world_id
        if changed then
            input_epoch = input_epoch + 1
            input_original, input_original_id, input_world_id = original, original_id, world_id
            if original then
                if not (active and active.external) then last_original = original end
                -- Correct the native price on first discovery, before F6/plus.
                refresh_cost(original)
            end
        else input_original = original end
        return original, changed
    end
    function controller.process_input() -- Game-thread frame callback/test entry.
        -- Drain atomically with respect to the Lua VM lock: until all mailbox
        -- cells are copied and cleared, there are no calls into C or UE.
        if not enabled or polling_job then return end
        local count, overflow = input_tail - input_head, input_overflow
        input_overflow = 0
        local i = 1
        while i <= count do
            local source, target = input_ring[input_head % INPUT_CAPACITY + 1], input_drain[i]
            target[1], target[2], target[3] = source[1], source[2], source[3]
            source[1], source[2], source[3] = 0, 0, 0
            input_head = input_head + 1
            i = i + 1
        end
        poll_queued() -- This frame entry is the sole executor of queued work.
        if queued then
            if count > 0 or overflow > 0 then queued_notice() end
            for index = 1, count do input_drain[index][1], input_drain[index][2], input_drain[index][3] = 0, 0, 0 end
            return
        end
        ensure_hooks(count > 0)
        -- Native Setup/ShowDialog maintain the target immediately. A single
        -- bootstrap/recovery scan covers a pre-existing or replaced dialog;
        -- ordinary gameplay with no panel performs no global object search.
        local recover_target = input_original_id ~= nil and not active and not visible_original(last_original)
        local scan = discovery_requested or count > 0 or recover_target
        discovery_requested = false
        local original, changed = observe_input_target(scan)
        local pending_context = type(api.needs_context_tick) == "function" and api.needs_context_tick()
        if type(api.tick_context) == "function" and (original or changed or count > 0 or pending_context) then
            local activated = api.tick_context() == true
            -- Context activation may retire a target from the previous world.
            original = observe_input_target(false)
            if activated and original then refresh_cost(original) end
        end
        local rejected = 0
        for index = 1, count do
            local cell = input_drain[index]
            local code, epoch = cell[1], cell[2]
            cell[1], cell[2], cell[3] = 0, 0, 0
            local original = observe_input_target(false)
            if not original or epoch ~= input_epoch then rejected = rejected + 1
            elseif blocked then
                controller.show_message("本次付款需要恢复，已停止后续加点。请保留日志，不要重复确认。")
                report("本次付款需要恢复，已停止后续加点。")
            elseif code == 6 then controller.next_page(original)
            elseif code == 7 then controller.close()
            elseif code == 8 then
                local ok, done, reason = pcall(function()
                    assert(type(api.prepare_uninstall) == "function", "准备卸载功能尚未就绪")
                    return api.prepare_uninstall()
                end)
                if not ok or not done then
                    local message = tostring(ok and reason or done)
                    controller.show_message(message); report("F8：" .. message)
                else input_epoch = input_epoch + 1 end
            end
        end
        if overflow > 0 then
            local message = "按键过快，超出的操作未执行，请重新按键。"
            controller.show_message(message); report(message)
        elseif rejected > 0 then
            local message = "窗口已变化，旧按键未执行；请在当前小幅改进窗口重新按键。"
            controller.show_message(message); report(message)
        end
    end
    function controller.start_input() -- Called only by the final GT bootstrap.
        if not enabled then return nil, "shutdown" end
        if input_loop then return true end
        assert(type(LoopInGameThreadAfterFrames) == "function", "game-thread frame timer unavailable")
        ensure_hooks()
        input_loop = LoopInGameThreadAfterFrames(1, safe("input frame", controller.process_input))
        return true
    end
    -- Install once while ui.install runs on main_lua. Never register these from
    -- ensure_hooks/retry_hooks or a game-thread callback (which uses hook_lua).
    RegisterKeyBind(Key.F6, function() enqueue_key(6) end)
    RegisterKeyBind(Key.F7, function() enqueue_key(7) end)
    RegisterKeyBind(Key.F8, function() enqueue_key(8) end)
    return controller
end

return M
