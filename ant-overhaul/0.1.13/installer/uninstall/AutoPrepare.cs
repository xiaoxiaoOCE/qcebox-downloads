using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

namespace AntOverhaulUninstall
{
    // Deliberately independent of UE4SS/the game. Only positively identified,
    // player-owned Health floats are changed; saves are never played or re-saved.
    public static class AutoPrepare
    {
        internal const string LedgerName = "EAA_AllAttributes_v1.tsv";
        internal const string ReadyName = "EAA_AllAttributes_v1.uninstall-ready.tsv";
        internal static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        static readonly Regex Identifier = new Regex("^[A-Za-z0-9][A-Za-z0-9_.:-]*$", RegexOptions.CultureInvariant);
        static readonly Regex SlotIdentifier = new Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", RegexOptions.CultureInvariant);
        static readonly Regex Fingerprint = new Regex("^[0-9a-f]{64}:[0-9a-f]{64}$", RegexOptions.CultureInvariant);
        static readonly Regex ShaPattern = new Regex("^[0-9a-f]{64}$", RegexOptions.CultureInvariant);
        static readonly HashSet<string> Stats = new HashSet<string>(new[] { "Health", "AttackDamage", "AttackSpeed", "Piercing", "MovementSpeed", "ResourceHarvest", "Armour", "VenomResistance", "PhysicalResistance", "OutOfCombatEvasion", "AreaOfEffectResistance", "Range", "Cooldown", "MaxDamageTaken" }, StringComparer.Ordinal);
        internal static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 16 * 1024 * 1024, RecursionLimit = 128 };

        public static int Main(string[] args)
        {
            Result result = new Result();
            Options options = null;
            string safeResult = null;
            try
            {
                options = Options.Parse(args);
                safeResult = ValidateResultPath(options);
                result.mode = options.Apply ? "apply" : "plan";
                Run(options, result, null);
            }
            catch (Exception ex)
            {
                result.success = false;
                if (result.status == "starting") result.status = "refused";
                result.message = ex.Message;
                result.log.Add("未完成自动卸载准备：" + ex.Message);
                Console.Error.WriteLine(ex.Message);
            }
            try
            {
                if (safeResult != null) WriteResult(safeResult, result);
                Console.WriteLine(Json.Serialize(result));
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("无法写入操作结果：" + ex.Message);
                return 1;
            }
            return result.success ? 0 : 1;
        }

        internal sealed class Options
        {
            public string SaveRoot, Reference, ResultPath;
            public bool Apply;
            public static Options Parse(string[] args)
            {
                Options o = new Options();
                HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
                for (int i = 0; i < args.Length; ++i)
                {
                    string key = args[i];
                    Need(seen.Add(key), "重复参数：" + key);
                    if (key == "--apply") { o.Apply = true; continue; }
                    Need(key == "--save-root" || key == "--reference" || key == "--result", "未知参数：" + key);
                    Need(++i < args.Length && !String.IsNullOrWhiteSpace(args[i]), "参数缺少值：" + key);
                    string path = Path.GetFullPath(args[i]);
                    if (key == "--save-root") o.SaveRoot = path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                    if (key == "--reference") o.Reference = path;
                    if (key == "--result") o.ResultPath = path;
                }
                Need(o.SaveRoot != null && o.Reference != null && o.ResultPath != null, "需要 --save-root、--reference 和 --result；不加 --apply 时只检查。");
                Need(!String.IsNullOrWhiteSpace(Path.GetFileName(o.SaveRoot)), "不能使用磁盘根目录作为存档目录。");
                return o;
            }
        }

        public sealed class Result
        {
            public int schemaVersion = 1;
            public bool success;
            public string mode = "plan", status = "starting", message, backupPath, referenceSha256;
            public bool applied, rollbackComplete;
            public int changedHealth, changedFiles;
            public bool requiresPreparation, requiresSaveChanges;
            public int slotCount, changedCreatureCount;
            public List<SlotResult> slots = new List<SlotResult>();
            public List<string> log = new List<string>();
        }

        public sealed class SlotResult
        {
            public string slot, status, beforeFingerprint, afterFingerprint;
            public int affectedCreatures, changedHealth;
        }

        internal static void Run(Options options, Result result, Action<int, string> afterReplace)
        {
            NoLinks(options.SaveRoot);
            Need(Directory.Exists(options.SaveRoot), "存档目录不存在。");
            NoLinks(options.Reference);
            Need(!Within(options.Reference, options.SaveRoot), "数值参考文件不能放在存档目录内。");
            CheckGameStopped();
            string mutexName = "Local\\AntOverhaulUninstall-" + Hash(Utf8.GetBytes(options.SaveRoot.ToUpperInvariant())).Substring(0, 32);
            using (Mutex mutex = new Mutex(false, mutexName))
            {
                bool locked = false;
                try
                {
                    try { locked = mutex.WaitOne(0); } catch (AbandonedMutexException) { locked = true; }
                    Need(locked, "另一个自动卸载准备正在处理这个存档目录。");
                    CheckNoPending(options.SaveRoot);
                    byte[] referenceBytes = ReadSmall(options.Reference, 8 * 1024 * 1024);
                    result.referenceSha256 = Hash(referenceBytes);
                    HealthReference reference = HealthReference.Read(referenceBytes);
                    if (options.Apply) Need(reference.Status == "validated", "原生生命值参考表尚未完成验证，未修改任何存档。");
                    Dictionary<string, FileState> original = Scan(options.SaveRoot);
                    string ledgerPath = Child(options.SaveRoot, LedgerName);
                    if (!File.Exists(ledgerPath))
                    {
                        Need(!File.Exists(ledgerPath + ".bak") && !File.Exists(Child(options.SaveRoot, ReadyName)), "主加点记录缺失但存在历史记录，不能猜测存档状态。");
                        VerifyTree(options.SaveRoot, original, null);
                        CheckGameStopped();
                        result.success = true; result.status = "no-ledger"; result.message = "没有扩展加点记录，无需准备存档。";
                        return;
                    }
                    Ledger ledger = Ledger.Read(ReadSmall(ledgerPath, 8 * 1024 * 1024), reference);
                    string readyPath = Child(options.SaveRoot, ReadyName);
                    SortedDictionary<string, string> ready = ReadReady(File.Exists(readyPath) ? ReadSmall(readyPath, 1024 * 1024) : null);
                    List<Change> changes = new List<Change>();
                    bool readyChanged = false, ledgerChanged = false;
                    foreach (KeyValuePair<string, LedgerSlot> entry in ledger.Slots)
                    {
                        string slotName = entry.Key;
                        Need(Regex.IsMatch(slotName, "^Colony[1-9][0-9]{0,8}$", RegexOptions.CultureInvariant), "不是已验证的故事养殖箱槽位：" + slotName);
                        LedgerSlot slot = entry.Value;
                        string mainPath = Child(options.SaveRoot, slotName + ".sav");
                        string levelPath = Child(options.SaveRoot, slotName + "LevelData.sav");
                        Need(File.Exists(mainPath) && File.Exists(levelPath), "存档 " + slotName + " 缺少主档或场景档，保留全部文件。" );
                        byte[] main = ReadSmall(mainPath, 512 * 1024 * 1024);
                        byte[] level = ReadSmall(levelPath, 512 * 1024 * 1024);
                        string fp = Hash(main) + ":" + Hash(level);
                        Need(fp == slot.Anchor, "存档 " + slotName + " 与加点记录指纹不一致，未猜测或丢弃点数。" );
                        SavePatcher.ValidateNativeMain(main);
                        SaveDocument document = SavePatcher.Read(level);
                        ValidateContext(document, slotName);
                        SlotResult sr = new SlotResult { slot = slotName, beforeFingerprint = fp, afterFingerprint = fp };
                        result.slots.Add(sr);
                        if (slot.Points.Count == 0) { sr.status = "no-extra-points"; continue; }
                        string readyFingerprint;
                        if (ready.TryGetValue(slotName, out readyFingerprint) && readyFingerprint == fp)
                        {
                            sr.status = "already-prepared";
                            continue;
                        }
                        Dictionary<int, float> caps = new Dictionary<int, float>();
                        bool anyHealth = slot.Points.Values.Any(p => p.ContainsKey("Health"));
                        if (anyHealth)
                        {
                            foreach (CreatureRecord creature in document.Creatures)
                            {
                                // A formicarium owns colony zero. Dead actors are not
                                // refreshed by the original F8 path and must stay dead.
                                if (creature.Owner != 0) continue;
                                Need(Finite(creature.Health), "存档 " + slotName + " 有无效生命值。");
                                if (creature.Health <= 0) continue;
                                HealthClass hc;
                                if (reference.Unaffected.Contains(creature.ClassPath)) continue;
                                Need(reference.Classes.TryGetValue(creature.ClassPath, out hc), "存档 " + slotName + " 的玩家单位类型未得到验证：" + creature.ClassPath);
                                bool affected = hc.Groups.Any(g => slot.Points.ContainsKey(g) && slot.Points[g].ContainsKey("Health"));
                                if (!affected) continue;
                                bool? foreign = creature.IsForeignSubTenant ?? reference.MissingForeignDefault;
                                Need(foreign.HasValue && !foreign.Value, "存档 " + slotName + " 存在无法安全计算的外来子单位：" + creature.ClassPath);
                                float baseHealth;
                                Need(hc.HealthByLevel.TryGetValue(creature.Level, out baseHealth), "存档 " + slotName + " 的单位等级未得到验证：" + creature.ClassPath + " / " + creature.Level);
                                Need(Finite(creature.SpawnStatScailing) && creature.SpawnStatScailing > 0, "存档 " + slotName + " 的生命值缩放无效。");
                                // Both inputs and the product are IEEE754 binary32,
                                // matching the game's native mulss instruction.
                                float cap = (float)(baseHealth * creature.SpawnStatScailing);
                                Need(Finite(cap) && cap > 0, "存档 " + slotName + " 的原生生命值上限无效。");
                                ++sr.affectedCreatures;
                                if (creature.Health > cap) { caps.Add(creature.Index, cap); ++sr.changedHealth; }
                            }
                        }
                        byte[] patched = document.Patch(caps);
                        string patchedHash = Hash(patched);
                        if (patchedHash != Hash(level))
                        {
                            VerifyHealthOnly(document, SavePatcher.Read(patched), caps);
                            changes.Add(new Change(levelPath, level, patched));
                            string newFp = Hash(main) + ":" + patchedHash;
                            ledger.Capture(slotName, newFp);
                            ledgerChanged = true;
                            sr.afterFingerprint = newFp;
                        }
                        else Need(caps.Count == 0, "生命值补丁没有产生预期变化。");
                        ready[slotName] = sr.afterFingerprint;
                        readyChanged = true;
                        sr.status = sr.changedHealth > 0 ? "health-cleanup" : "mark-prepared";
                        result.changedHealth += sr.changedHealth;
                    }
                    if (ledgerChanged) changes.Add(new Change(ledgerPath, File.ReadAllBytes(ledgerPath), ledger.Encode()));
                    if (readyChanged) changes.Add(new Change(readyPath, File.Exists(readyPath) ? File.ReadAllBytes(readyPath) : null, EncodeReady(ready)));
                    foreach (Change c in changes)
                    {
                        FileState baseline;
                        if (original.TryGetValue(Relative(options.SaveRoot, c.Path), out baseline)) Need(c.Before != null && Hash(c.Before) == baseline.Hash, "规划期间源文件发生变化：" + c.Path);
                        else Need(c.Before == null, "规划期间源文件发生变化：" + c.Path);
                    }
                    VerifyTree(options.SaveRoot, original, null);
                    CheckGameStopped();
                    result.changedFiles = changes.Count;
                    result.requiresPreparation = readyChanged;
                    result.requiresSaveChanges = result.changedHealth > 0;
                    result.slotCount = result.slots.Count;
                    result.changedCreatureCount = result.changedHealth;
                    if (!options.Apply || changes.Count == 0)
                    {
                        result.success = true;
                        result.status = changes.Count == 0 ? "already-prepared" : "planned";
                        result.message = changes.Count == 0 ? "所有扩展加点存档均已准备好，无需改动。" : "检查通过：将自动准备 " + result.slots.Count(s => s.status == "health-cleanup" || s.status == "mark-prepared") + " 个存档，清理 " + result.changedHealth + " 个单位的残留生命值。";
                        return;
                    }
                    Apply(options.SaveRoot, original, changes, result, afterReplace);
                    result.success = true; result.applied = true; result.status = "prepared";
                    result.message = "所有扩展加点存档已自动准备，原存档和全部加点记录已备份。";
                }
                finally { if (locked) mutex.ReleaseMutex(); }
            }
        }

        static void ValidateContext(SaveDocument doc, string slot)
        {
            // These metadata fields are absent in native formicarium saves.
            // Context is established by the verified ColonyN pair + UFormicSave
            // root + stable ledger anchor, not by inventing absent tag defaults.
            Need(!doc.HasOwnedColonyIds || (doc.OwnedColonyIds.Count == 1 && doc.OwnedColonyIds[0] == 0), "存档 " + slot + " 的玩家归属与养殖箱不符。");
            Need(!doc.StartingColonyId.HasValue || doc.StartingColonyId.Value == 0, "存档 " + slot + " 的起始殖民地与养殖箱不符。");
            Need(String.IsNullOrEmpty(doc.LinkedFormicariumSave) || doc.LinkedFormicariumSave == slot, "存档 " + slot + " 链接了另一个养殖箱存档。");
        }

        static void VerifyHealthOnly(SaveDocument before, SaveDocument after, IDictionary<int, float> caps)
        {
            byte[] a = before.GetGvasBytes(), b = after.GetGvasBytes();
            Need(a.Length == b.Length && before.Creatures.Count == after.Creatures.Count, "补丁改变了存档结构。");
            HashSet<int> allowed = new HashSet<int>();
            foreach (CreatureRecord c in before.Creatures)
            {
                float cap;
                if (!caps.TryGetValue(c.Index, out cap)) continue;
                CreatureRecord d = after.Creatures[c.Index];
                Need(c.HealthOffset == d.HealthOffset && d.Health == Math.Min(c.Health, cap), "生命值补丁验证失败。");
                for (int j = 0; j < 4; ++j) allowed.Add(c.HealthOffset + j);
            }
            for (int i = 0; i < a.Length; ++i) Need(a[i] == b[i] || allowed.Contains(i), "补丁改变了生命值以外的存档数据。");
        }

        internal sealed class Change
        {
            public string Path, Temp, AfterHash;
            public byte[] Before, After;
            public bool Committed, Attempted;
            public Change(string path, byte[] before, byte[] after) { Path = path; Before = before; After = after; AfterHash = Hash(after); }
        }
        internal sealed class FileState { public string Hash; public long Length; }

        internal static void Apply(string root, Dictionary<string, FileState> original, List<Change> changes, Result result, Action<int, string> afterReplace)
        {
            string token = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture) + "-" + Guid.NewGuid().ToString("N");
            string backupParent = Child(Path.GetDirectoryName(root), "EAA-uninstall-backups");
            string backup = Child(backupParent, token);
            string backupSaves = Child(backup, "SaveGames");
            string pending = Child(root, LedgerName + ".pending");
            bool ownsPending = false, rollbackOk = true;
            byte[] pendingBytes = null;
            HashSet<string> temporary = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                CheckGameStopped(); CheckNoPending(root); VerifyTree(root, original, null);
                NoLinks(backupParent);
                Directory.CreateDirectory(backupSaves);
                result.backupPath = backup;
                foreach (KeyValuePair<string, FileState> file in original)
                {
                    string from = Child(root, file.Key), to = Child(backupSaves, file.Key);
                    NoLinks(from); NoLinks(to);
                    Directory.CreateDirectory(Path.GetDirectoryName(to));
                    File.Copy(from, to, false);
                    Need(FileHash(to) == file.Value.Hash, "备份验证失败：" + file.Key);
                }
                VerifyTree(root, original, null);
                Dictionary<string, object> manifest = new Dictionary<string, object>();
                manifest["schemaVersion"] = 1; manifest["saveRoot"] = root; manifest["createdUtc"] = DateTime.UtcNow.ToString("o");
                manifest["originalFiles"] = original; manifest["changedFiles"] = changes.Select(c => new { path = Relative(root, c.Path), originalSha256 = c.Before == null ? null : Hash(c.Before), candidateSha256 = c.AfterHash }).ToArray();
                WriteNew(Child(backup, "transaction.json"), Utf8.GetBytes(Json.Serialize(manifest)));
                result.log.Add("已完整备份存档目录：" + backupSaves);
                foreach (Change change in changes)
                {
                    change.Temp = Child(root, "." + Path.GetFileName(change.Path) + ".eaa-uninstall-" + token + ".tmp");
                    WriteTemporary(change.Temp, change.After, root, temporary);
                    Need(FileHash(change.Temp) == change.AfterHash, "候选文件写入验证失败。");
                }
                CheckGameStopped(); CheckNoPending(root); VerifyTree(root, original, temporary);
                // The existing mod refuses any .pending journal. A killed worker
                // therefore cannot let a partial ledger be silently used in-game.
                pendingBytes = Utf8.GetBytes("EAA_AUTOPREPARE_PENDING_V1\n" + Json.Serialize(new { backupPath = backup, saveRoot = root, token = token }) + "\n");
                NoLinks(pending);
                using (FileStream journal = new FileStream(pending, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    ownsPending = true;
                    journal.Write(pendingBytes, 0, pendingBytes.Length); journal.Flush(true);
                }
                temporary.Add(Relative(root, pending));
                int written = 0;
                foreach (Change change in changes)
                {
                    CheckGameStopped();
                    VerifyExpected(root, original, changes, temporary);
                    Need(File.ReadAllBytes(pending).SequenceEqual(pendingBytes), "准备事务标记已变化。");
                    NoLinks(change.Path); NoLinks(change.Temp);
                    change.Attempted = true;
                    if (change.Before == null) File.Move(change.Temp, change.Path);
                    else File.Replace(change.Temp, change.Path, null);
                    change.Committed = true;
                    Need(FileHash(change.Path) == change.AfterHash, "提交后文件校验失败：" + change.Path);
                    ++written;
                    if (afterReplace != null) afterReplace(written, change.Path);
                }
                CheckGameStopped(); VerifyExpected(root, original, changes, temporary);
                Need(File.ReadAllBytes(pending).SequenceEqual(pendingBytes), "准备事务标记已变化。");
                File.Delete(pending); ownsPending = false;
                result.success = true; result.applied = true; result.status = "prepared";
                result.log.Add("已验证全部生命值补丁、加点记录新指纹和卸载标记。历史 Stage、自动备份和 .bak 文件未改动。");
            }
            catch (Exception ex)
            {
                result.status = "failed";
                result.log.Add("准备未完成，开始恢复本次已提交文件：" + ex.Message);
                foreach (Change change in changes.AsEnumerable().Reverse())
                {
                    if (!change.Attempted) continue;
                    try
                    {
                        NoLinks(change.Path);
                        bool exists = File.Exists(change.Path);
                        string currentHash = exists ? FileHash(change.Path) : null;
                        string beforeHash = change.Before == null ? null : Hash(change.Before);
                        // A replacement can report an error after its rename was
                        // committed. Trust the bytes on disk, not only the call's
                        // return value. Any third state stays blocked for recovery.
                        if (currentHash == beforeHash) { change.Committed = false; continue; }
                        Need(exists && currentHash == change.AfterHash, "文件被其他程序改动或缺失，未覆盖：" + change.Path);
                        if (change.Before == null) File.Delete(change.Path);
                        else
                        {
                            string restore = Child(root, "." + Path.GetFileName(change.Path) + ".eaa-restore-" + token + ".tmp");
                            WriteTemporary(restore, change.Before, root, temporary);
                            File.Replace(restore, change.Path, null);
                            Need(FileHash(change.Path) == Hash(change.Before), "恢复验证失败：" + change.Path);
                        }
                        change.Committed = false;
                    }
                    catch (Exception restoreError) { rollbackOk = false; result.log.Add(restoreError.Message); }
                }
                foreach (Change change in changes.Where(c => c.Attempted))
                {
                    try
                    {
                        NoLinks(change.Path);
                        Need(change.Before == null ? !File.Exists(change.Path) : File.Exists(change.Path) && FileHash(change.Path) == Hash(change.Before), "回滚后的原文件核验失败：" + change.Path);
                    }
                    catch (Exception verifyError) { rollbackOk = false; result.log.Add(verifyError.Message); }
                }
                if (ownsPending && rollbackOk)
                {
                    try { Need(File.ReadAllBytes(pending).SequenceEqual(pendingBytes), "事务标记已被改动。"); File.Delete(pending); ownsPending = false; }
                    catch (Exception pendingError) { rollbackOk = false; result.log.Add(pendingError.Message); }
                }
                result.rollbackComplete = rollbackOk;
                result.status = rollbackOk ? "rolled-back" : "recovery-required";
                if (!rollbackOk) throw new IOException("自动准备失败且恢复未全部完成。未允许卸载；完整备份位于 " + backup + "。原因：" + ex.Message, ex);
                throw new IOException("自动准备失败，已恢复本次修改。模组应保留。备份：" + backup + "。原因：" + ex.Message, ex);
            }
            finally
            {
                foreach (string rel in temporary)
                {
                    string path = Child(root, rel);
                    if (String.Equals(path, pending, StringComparison.OrdinalIgnoreCase)) continue;
                    try { NoLinks(path); if (File.Exists(path)) File.Delete(path); }
                    catch (Exception cleanupError) { result.log.Add("临时文件保留：" + path + "；" + cleanupError.Message); }
                }
                if (result.backupPath != null)
                {
                    try { WriteNew(Child(backup, "operation-log.json"), Utf8.GetBytes(Json.Serialize(result))); }
                    catch (Exception logError) { result.log.Add("备份日志写入失败：" + logError.Message); }
                }
            }
        }

        static void VerifyExpected(string root, Dictionary<string, FileState> original, List<Change> changes, HashSet<string> ignored)
        {
            Dictionary<string, FileState> expected = new Dictionary<string, FileState>(original, StringComparer.OrdinalIgnoreCase);
            foreach (Change change in changes.Where(c => c.Committed)) expected[Relative(root, change.Path)] = new FileState { Hash = change.AfterHash, Length = change.After.LongLength };
            VerifyTree(root, expected, ignored);
        }

        internal static Dictionary<string, FileState> Scan(string root)
        {
            Dictionary<string, FileState> files = new Dictionary<string, FileState>(StringComparer.OrdinalIgnoreCase);
            Stack<string> dirs = new Stack<string>(); dirs.Push(root);
            while (dirs.Count > 0)
            {
                string dir = dirs.Pop(); NoLinks(dir);
                foreach (string path in Directory.GetFileSystemEntries(dir))
                {
                    NoLinks(path);
                    FileAttributes attr = File.GetAttributes(path);
                    if ((attr & FileAttributes.Directory) != 0) { dirs.Push(path); continue; }
                    string rel = Relative(root, path);
                    Need(!files.ContainsKey(rel), "存档目录存在大小写冲突路径。");
                    files.Add(rel, new FileState { Hash = FileHash(path), Length = new FileInfo(path).Length });
                    Need(files.Count <= 100000, "存档目录文件数量超出安全范围。");
                }
            }
            return files;
        }

        static void VerifyTree(string root, Dictionary<string, FileState> expected, HashSet<string> ignored)
        {
            Dictionary<string, FileState> actual = Scan(root);
            if (ignored != null) foreach (string p in ignored) actual.Remove(p);
            Need(actual.Count == expected.Count, "存档目录在准备过程中发生变化，未继续提交。");
            foreach (KeyValuePair<string, FileState> item in expected)
            {
                FileState observed;
                Need(actual.TryGetValue(item.Key, out observed) && observed.Hash == item.Value.Hash && observed.Length == item.Value.Length, "存档文件在准备过程中发生变化：" + item.Key);
            }
        }

        static void CheckNoPending(string root)
        {
            foreach (string name in new[] { LedgerName + ".pending", LedgerName + ".tmp", ReadyName + ".tmp" }) Need(!File.Exists(Child(root, name)), "存在未完成事务 " + name + "，未改动存档。请先恢复该事务。");
        }

        static void CheckGameStopped()
        {
            foreach (string name in new[] { "EotU", "EotU-Win64-Shipping" })
            {
                Process[] found = Process.GetProcessesByName(name);
                bool running = found.Length != 0;
                foreach (Process p in found) p.Dispose();
                Need(!running, "请先完全退出地下蚁国，再进行自动卸载准备。");
            }
        }

        internal sealed class LedgerSlot
        {
            public string Anchor;
            public SortedDictionary<string, SortedDictionary<string, int>> Points = PointsNew();
            public SortedDictionary<string, SortedDictionary<string, SortedDictionary<string, int>>> Snapshots = new SortedDictionary<string, SortedDictionary<string, SortedDictionary<string, int>>>(StringComparer.Ordinal);
        }

        internal sealed class Ledger
        {
            public int Revision;
            public SortedDictionary<string, LedgerSlot> Slots = new SortedDictionary<string, LedgerSlot>(StringComparer.Ordinal);
            public static Ledger Read(byte[] bytes, HealthReference reference)
            {
                Need(bytes.Length <= 8 * 1024 * 1024, "加点记录太大。");
                string[] lines = Lines(bytes);
                Need(lines.Length >= 2 && lines.Length <= 100000 && lines[0] == "EOTU_ALL_ATTRIBUTES\t1", "加点记录版本不支持。");
                string[] rev = lines[1].Split('\t');
                Need(rev.Length == 2 && rev[0] == "REV", "加点记录缺少版本计数。");
                Ledger ledger = new Ledger { Revision = Integer(rev[1], 0) };
                for (int i = 2; i < lines.Length; ++i)
                {
                    string[] f = lines[i].Split('\t');
                    Need(f.Length >= 2, "无效加点记录行。");
                    LedgerSlot slot;
                    if (f[0] == "SLOT" && f.Length == 3)
                    {
                        Need(SlotIdentifier.IsMatch(f[1]) && Fingerprint.IsMatch(f[2]) && !ledger.Slots.ContainsKey(f[1]), "无效或重复的存档记录。");
                        ledger.Slots.Add(f[1], new LedgerSlot { Anchor = f[2] });
                    }
                    else if (f[0] == "POINT" && f.Length == 5)
                    {
                        Need(ledger.Slots.TryGetValue(f[1], out slot), "加点记录引用了未知存档。");
                        InsertPoint(slot.Points, f[2], f[3], f[4], reference);
                    }
                    else if (f[0] == "SNAP" && f.Length == 3)
                    {
                        Need(ledger.Slots.TryGetValue(f[1], out slot) && Fingerprint.IsMatch(f[2]) && !slot.Snapshots.ContainsKey(f[2]), "无效或重复的历史指纹。");
                        slot.Snapshots.Add(f[2], PointsNew());
                    }
                    else if (f[0] == "SNAPPOINT" && f.Length == 6)
                    {
                        Need(ledger.Slots.TryGetValue(f[1], out slot) && slot.Snapshots.ContainsKey(f[2]), "历史加点引用了未知指纹。");
                        InsertPoint(slot.Snapshots[f[2]], f[3], f[4], f[5], reference);
                    }
                    else throw new InvalidDataException("未知加点记录类型。");
                }
                foreach (LedgerSlot slot in ledger.Slots.Values)
                {
                    Need(slot.Snapshots.ContainsKey(slot.Anchor) && PointsEqual(slot.Points, slot.Snapshots[slot.Anchor]), "加点记录尚未稳定保存，未继续准备。");
                    ValidateSums(slot.Points, reference);
                    foreach (var snapshot in slot.Snapshots.Values) ValidateSums(snapshot, reference);
                }
                return ledger;
            }
            public void Capture(string slotName, string fingerprint)
            {
                LedgerSlot slot = Slots[slotName];
                Need(!slot.Snapshots.ContainsKey(fingerprint) || PointsEqual(slot.Snapshots[fingerprint], slot.Points), "新指纹与历史点数冲突。");
                if (slot.Anchor == fingerprint && slot.Snapshots.ContainsKey(fingerprint)) return;
                Need(Revision < Int32.MaxValue, "加点记录版本计数已溢出。");
                slot.Snapshots[fingerprint] = ClonePoints(slot.Points); slot.Anchor = fingerprint; ++Revision;
            }
            public byte[] Encode()
            {
                List<string> lines = new List<string> { "EOTU_ALL_ATTRIBUTES\t1", "REV\t" + Revision.ToString(CultureInfo.InvariantCulture) };
                foreach (var pair in Slots)
                {
                    string name = pair.Key; LedgerSlot slot = pair.Value;
                    lines.Add("SLOT\t" + name + "\t" + slot.Anchor);
                    AddPoints(lines, "POINT\t" + name, slot.Points);
                    foreach (var snapshot in slot.Snapshots)
                    {
                        lines.Add("SNAP\t" + name + "\t" + snapshot.Key);
                        AddPoints(lines, "SNAPPOINT\t" + name + "\t" + snapshot.Key, snapshot.Value);
                    }
                }
                byte[] bytes = Utf8.GetBytes(String.Join("\n", lines.ToArray()) + "\n");
                Need(lines.Count <= 100000 && bytes.Length <= 8 * 1024 * 1024, "更新后的加点记录超出大小限制。");
                return bytes;
            }
        }

        static void InsertPoint(SortedDictionary<string, SortedDictionary<string, int>> points, string group, string stat, string count, HealthReference reference)
        {
            Need(group.Length <= 128 && Identifier.IsMatch(group) && stat.Length <= 64 && Identifier.IsMatch(stat), "加点记录标识无效。");
            HealthGroup definition;
            Need(reference.Groups.TryGetValue(group, out definition) && Stats.Contains(stat), "加点记录含有不受支持的兵种或属性：" + group + " / " + stat);
            Need(!definition.NativeStats.Contains(stat), "原生属性被错误写入扩展加点记录：" + group + " / " + stat);
            SortedDictionary<string, int> entries;
            if (!points.TryGetValue(group, out entries)) { entries = new SortedDictionary<string, int>(StringComparer.Ordinal); points.Add(group, entries); }
            Need(!entries.ContainsKey(stat), "重复的加点记录。");
            entries.Add(stat, Integer(count, 1));
        }

        static void ValidateSums(SortedDictionary<string, SortedDictionary<string, int>> points, HealthReference reference)
        {
            Dictionary<string, long> expanded = new Dictionary<string, long>(StringComparer.Ordinal);
            foreach (var group in points)
            {
                Need(group.Value.Values.Sum(n => (long)n) <= Int32.MaxValue, "兵种点数溢出。");
                foreach (string alias in reference.Groups[group.Key].Aliases)
                    foreach (var stat in group.Value)
                    {
                        string key = alias + "\t" + stat.Key;
                        long value; expanded.TryGetValue(key, out value); value += stat.Value;
                        Need(value <= Int32.MaxValue, "继承兵种点数溢出。"); expanded[key] = value;
                    }
            }
        }

        internal sealed class HealthGroup { public string Id; public string[] Aliases; public HashSet<string> NativeStats; }
        internal sealed class HealthClass { public string Name; public string[] Groups; public Dictionary<int, float> HealthByLevel = new Dictionary<int, float>(); }
        internal sealed class HealthReference
        {
            public string Status;
            public bool? MissingForeignDefault;
            public Dictionary<string, HealthGroup> Groups = new Dictionary<string, HealthGroup>(StringComparer.Ordinal);
            public Dictionary<string, HealthClass> Classes = new Dictionary<string, HealthClass>(StringComparer.Ordinal);
            public HashSet<string> Unaffected = new HashSet<string>(StringComparer.Ordinal);
            public static HealthReference Read(byte[] bytes)
            {
                Dictionary<string, object> data = Map(Json.DeserializeObject(Utf8.GetString(bytes)));
                Need(Convert.ToInt32(Value(data, "schemaVersion"), CultureInfo.InvariantCulture) == 1, "生命值参考表版本不支持。");
                Dictionary<string, object> build = Map(Value(data, "gameBuild"));
                Need(Text(Value(build, "steamAppId")) == "463530" && Text(Value(build, "steamBuildId")) == "26119497" && Text(Value(build, "gameVersion")) == "1.2.1.1", "生命值参考表不适用于当前支持的游戏版本。");
                Need(ShaPattern.IsMatch(Text(Value(build, "executableSha256"))), "生命值参考表缺少有效的游戏指纹。");
                Need(ArrayOf(Value(data, "unsupportedNames")).Length == 0, "生命值参考表仍有未验证的兵种。");
                HealthReference reference = new HealthReference { Status = Text(Value(data, "status")) };
                object missingDefault;
                if (data.TryGetValue("missingForeignDefault", out missingDefault))
                {
                    Need(missingDefault is bool && !(bool)missingDefault, "未验证的旧存档外来单位默认值。");
                    Dictionary<string, object> evidence = Map(Value(data, "missingForeignDefaultEvidence"));
                    int count = Convert.ToInt32(Value(evidence, "serializedMissingCount"), CultureInfo.InvariantCulture);
                    Need(count > 0 && Convert.ToInt32(Value(evidence, "nativeFalseCount"), CultureInfo.InvariantCulture) == count
                        && Convert.ToInt32(Value(evidence, "nativeTrueCount"), CultureInfo.InvariantCulture) == 0
                        && Convert.ToInt32(Value(evidence, "identityMatches"), CultureInfo.InvariantCulture) == count
                        && ShaPattern.IsMatch(Text(Value(evidence, "sha256"))), "旧存档默认值缺少完整原生对照证据。");
                    reference.MissingForeignDefault = false;
                }
                foreach (object raw in ArrayOf(Value(data, "groups")))
                {
                    Dictionary<string, object> obj = Map(raw);
                    string id = Text(Value(obj, "id"));
                    Need(id.Length <= 128 && Identifier.IsMatch(id) && !reference.Groups.ContainsKey(id), "生命值参考表有无效或重复的兵种组。");
                    string[] aliases = Strings(Value(obj, "aliases")), nativeStats = Strings(Value(obj, "nativeStats"));
                    Need(aliases.Length > 0 && aliases.Distinct(StringComparer.Ordinal).Count() == aliases.Length && aliases.All(a => a.Length <= 128 && Identifier.IsMatch(a)), "兵种别名无效。");
                    Need(nativeStats.All(s => Stats.Contains(s)) && nativeStats.Distinct(StringComparer.Ordinal).Count() == nativeStats.Length, "原生属性清单无效。");
                    Need((bool)Value(obj, "nativeHealth") == nativeStats.Contains("Health"), "原生生命值定义不一致。");
                    reference.Groups.Add(id, new HealthGroup { Id = id, Aliases = aliases, NativeStats = new HashSet<string>(nativeStats, StringComparer.Ordinal) });
                }
                foreach (object raw in ArrayOf(Value(data, "classes")))
                {
                    Dictionary<string, object> obj = Map(raw);
                    string path = ClassPath(Value(obj, "classPath")), name = Text(Value(obj, "creatureName"));
                    string[] groups = Strings(Value(obj, "groupIds"));
                    ValidateClassGroups(reference, groups, name, false);
                    HealthClass hc = new HealthClass { Name = name, Groups = groups };
                    foreach (var hp in Map(Value(obj, "healthByLevel")))
                    {
                        int level = Integer(hp.Key, 1);
                        float health = Convert.ToSingle(hp.Value, CultureInfo.InvariantCulture);
                        Need(Finite(health) && health > 0, "原生生命值参考无效。");
                        hc.HealthByLevel.Add(level, health);
                    }
                    Need(hc.HealthByLevel.Count > 0 && !reference.Classes.ContainsKey(path), "重复或缺失的兵种生命值参考。");
                    reference.Classes.Add(path, hc);
                }
                foreach (object raw in ArrayOf(Value(data, "unaffectedClasses")))
                {
                    Dictionary<string, object> obj = Map(raw);
                    string path = ClassPath(Value(obj, "classPath"));
                    string[] groups = Strings(Value(obj, "groupIds"));
                    string name = Text(Value(obj, "creatureName"));
                    if (groups.Length == 0)
                        Need(!(bool)Value(obj, "nativeHealth") && Text(Value(obj, "reason")) == "not_an_extra_Health_alias_in_groups" && !reference.Groups.Values.Any(g => g.Aliases.Contains(name)), "原生非加点单位定义不一致。");
                    else
                    {
                        Need((bool)Value(obj, "nativeHealth"), "不受影响的加点组必须使用原生生命属性。");
                        ValidateClassGroups(reference, groups, name, true);
                    }
                    Need(!reference.Classes.ContainsKey(path) && reference.Unaffected.Add(path), "重复的原生兵种参考。");
                }
                Need(reference.Groups.Count > 0 && reference.Classes.Count > 0 && reference.Unaffected.Count > 0, "生命值参考表不完整。");
                return reference;
            }
        }

        static void ValidateClassGroups(HealthReference reference, string[] groups, string name, bool nativeHealth)
        {
            Need(groups.Length > 0 && groups.Distinct(StringComparer.Ordinal).Count() == groups.Length, "兵种类型对应组无效。");
            foreach (string id in groups)
            {
                HealthGroup group;
                Need(reference.Groups.TryGetValue(id, out group) && group.Aliases.Contains(name) && group.NativeStats.Contains("Health") == nativeHealth, "兵种类型与加点组不匹配：" + name);
            }
            string[] all = reference.Groups.Values.Where(g => g.Aliases.Contains(name)).Select(g => g.Id).OrderBy(g => g, StringComparer.Ordinal).ToArray();
            Need(all.SequenceEqual(groups.OrderBy(g => g, StringComparer.Ordinal)), "兵种继承组清单不完整：" + name);
        }

        static string ClassPath(object raw) { string path = Text(raw); Need(path.StartsWith("/Game/", StringComparison.Ordinal) && path.EndsWith("_C", StringComparison.Ordinal) && path.IndexOf('\0') < 0, "兵种类路径无效。"); return path; }
        static Dictionary<string, object> Map(object o) { Dictionary<string, object> d = o as Dictionary<string, object>; Need(d != null, "参考表对象格式无效。"); return d; }
        static object Value(Dictionary<string, object> d, string key) { object v; Need(d.TryGetValue(key, out v), "参考表缺少字段：" + key); return v; }
        static object[] ArrayOf(object o) { object[] a = o as object[]; Need(a != null, "参考表数组格式无效。"); return a; }
        static string Text(object o) { string s = o as string; Need(s != null, "参考表文本格式无效。"); return s; }
        static string[] Strings(object o) { return ArrayOf(o).Select(Text).ToArray(); }

        static SortedDictionary<string, SortedDictionary<string, int>> PointsNew() { return new SortedDictionary<string, SortedDictionary<string, int>>(StringComparer.Ordinal); }
        static SortedDictionary<string, SortedDictionary<string, int>> ClonePoints(SortedDictionary<string, SortedDictionary<string, int>> points) { var p = PointsNew(); foreach (var group in points) p.Add(group.Key, new SortedDictionary<string, int>(group.Value, StringComparer.Ordinal)); return p; }
        static bool PointsEqual(SortedDictionary<string, SortedDictionary<string, int>> a, SortedDictionary<string, SortedDictionary<string, int>> b) { return a.Count == b.Count && a.All(g => b.ContainsKey(g.Key) && g.Value.Count == b[g.Key].Count && g.Value.All(s => b[g.Key].ContainsKey(s.Key) && b[g.Key][s.Key] == s.Value)); }
        static void AddPoints(List<string> lines, string prefix, SortedDictionary<string, SortedDictionary<string, int>> points) { foreach (var group in points) foreach (var stat in group.Value) lines.Add(prefix + "\t" + group.Key + "\t" + stat.Key + "\t" + stat.Value.ToString(CultureInfo.InvariantCulture)); }

        static SortedDictionary<string, string> ReadReady(byte[] bytes)
        {
            var ready = new SortedDictionary<string, string>(StringComparer.Ordinal);
            if (bytes == null) return ready;
            string[] lines = Lines(bytes);
            Need(lines.Length >= 1 && lines[0] == "EAA_UNINSTALL_READY_V1", "卸载标记版本无效。");
            for (int i = 1; i < lines.Length; ++i)
            {
                string[] f = lines[i].Split('\t');
                Need(f.Length == 3 && f[0] == "SLOT" && SlotIdentifier.IsMatch(f[1]) && Fingerprint.IsMatch(f[2]) && !ready.ContainsKey(f[1]), "卸载标记无效或重复。");
                ready.Add(f[1], f[2]);
            }
            return ready;
        }
        static byte[] EncodeReady(SortedDictionary<string, string> ready) { return Utf8.GetBytes("EAA_UNINSTALL_READY_V1\n" + String.Concat(ready.Select(p => "SLOT\t" + p.Key + "\t" + p.Value + "\n"))); }
        static string[] Lines(byte[] bytes) { string text = Utf8.GetString(bytes).Replace("\r\n", "\n"); Need(text.EndsWith("\n", StringComparison.Ordinal) && text.IndexOf('\r') < 0 && text.IndexOf('\0') < 0, "记录文件格式不完整。"); return text.Substring(0, text.Length - 1).Split('\n'); }
        static int Integer(string raw, int min) { int n; Need(raw.Length <= 10 && Regex.IsMatch(raw, "^(0|[1-9][0-9]*)$", RegexOptions.CultureInvariant) && Int32.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out n) && n >= min, "无效整数记录。"); return Int32.Parse(raw, CultureInfo.InvariantCulture); }
        static bool Finite(float v) { return !Single.IsNaN(v) && !Single.IsInfinity(v); }
        internal static void Need(bool condition, string message) { if (!condition) throw new InvalidDataException(message); }
        internal static string Hash(byte[] bytes) { using (SHA256 sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant(); }
        static string FileHash(string path) { NoLinks(path); using (FileStream file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) using (SHA256 sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant(); }
        static byte[] ReadSmall(string path, int maximum) { NoLinks(path); Need(new FileInfo(path).Length <= maximum, "文件超出安全读取范围：" + path); return File.ReadAllBytes(path); }
        static bool Within(string path, string root) { string p = Path.GetFullPath(path), r = Path.GetFullPath(root).TrimEnd('\\', '/'); return p.Equals(r, StringComparison.OrdinalIgnoreCase) || p.StartsWith(r + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase); }
        internal static string Child(string root, string relative) { Need(!Path.IsPathRooted(relative) && relative.IndexOf(':') < 0 && !relative.Split('\\', '/').Any(s => s == ".." || s == "."), "不安全的相对路径。"); string full = Path.GetFullPath(Path.Combine(root, relative)); Need(Within(full, root) && !full.Equals(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase), "路径越界。"); return full; }
        static string Relative(string root, string path) { Need(Within(path, root), "路径越界。"); return Path.GetFullPath(path).Substring(Path.GetFullPath(root).TrimEnd('\\', '/').Length + 1); }
        static void NoLinks(string path)
        {
            string full = Path.GetFullPath(path);
            while (!String.IsNullOrEmpty(full))
            {
                try { Need((File.GetAttributes(full) & FileAttributes.ReparsePoint) == 0, "不处理链接或重定向目录：" + full); }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
                string parent = Path.GetDirectoryName(full);
                if (String.Equals(parent, full, StringComparison.OrdinalIgnoreCase)) break;
                full = parent;
            }
        }
        static void WriteNew(string path, byte[] bytes) { NoLinks(path); using (FileStream f = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { f.Write(bytes, 0, bytes.Length); f.Flush(true); } }
        static void WriteTemporary(string path, byte[] bytes, string root, HashSet<string> owned)
        {
            NoLinks(path);
            using (FileStream f = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                owned.Add(Relative(root, path));
                f.Write(bytes, 0, bytes.Length); f.Flush(true);
            }
        }
        static string ValidateResultPath(Options options) { Need(!Within(options.ResultPath, options.SaveRoot) && !options.ResultPath.Equals(options.Reference, StringComparison.OrdinalIgnoreCase), "结果文件必须位于存档目录之外，且不能覆盖参考表。"); NoLinks(options.ResultPath); Need(Directory.Exists(Path.GetDirectoryName(options.ResultPath)), "结果文件的父目录不存在。"); return options.ResultPath; }
        static void WriteResult(string path, Result result)
        {
            NoLinks(path);
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            WriteNew(temp, Utf8.GetBytes(Json.Serialize(result)));
            try { if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path); }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
}
