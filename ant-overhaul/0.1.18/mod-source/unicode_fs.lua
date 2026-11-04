-- UTF-8 path adapter for the Windows UCRT used by this UE4SS build.
-- Import does not change locale or replace global io/os functions. ASCII paths
-- take the original fast path. Non-ASCII pathname operations temporarily use
-- UTF-8 LC_CTYPE and restore it before returning a handle or any error.
-- No yield/callback/engine work is performed inside that scope. LC_NUMERIC and
-- all other categories are untouched. Without CRT per-thread locale enabled,
-- the short scope can also be observed by other threads sharing LC_CTYPE.
local M={}
function M.new(options)
 options=options or{}
 local open=options.open or io.open
 local remove=options.remove or os.remove
 local rename=options.rename or os.rename
 local setlocale=options.setlocale or os.setlocale
 local function unicode(path)
  return type(path)=='string'and path:find('[\128-\255]')~=nil
 end
 local function valid_path(path)
  if type(path)~='string'then return true end -- Preserve the native argument error.
  if path:find('\0',1,true)then return nil,'unicode_fs_path_contains_nul',22 end
  if unicode(path)and not utf8.len(path)then return nil,'unicode_fs_path_invalid_utf8',22 end
  return true
 end
 local function close_failed_handle(operation,result)
  if operation=='open'and result and result[1]and result[2]then
   pcall(function()result[2]:close()end)
  end
 end
 local function scoped(operation,fn,...)
  local prior=setlocale(nil,'ctype')
  if type(prior)~='string'then return nil,'unicode_fs_ctype_query_failed',22 end
  local entered=table.pack(pcall(setlocale,'.UTF8','ctype'))
  local codepage=entered[1]and type(entered[2])=='string'and entered[2]:match('%.([^%.]+)$')
  codepage=codepage and codepage:lower():gsub('%-','')
  local result
  if codepage=='utf8'or codepage=='65001'then result=table.pack(pcall(fn,...))end
  -- Always restore, including an unavailable UTF-8 locale or thrown I/O call.
  local restored=table.pack(pcall(setlocale,prior,'ctype'))
  if not restored[1]or restored[2]~=prior then
   close_failed_handle(operation,result)
   error('unicode_fs_ctype_restore_failed: '..tostring(restored[2]),0)
  end
  if not result then return nil,'unicode_fs_utf8_unavailable: '..tostring(entered[2]),22 end
  if not result[1]then error(result[2],0)end
  return table.unpack(result,2,result.n)
 end
 local fs={}
 function fs.open(path,mode)
  local ok,e,code=valid_path(path);if not ok then return nil,e,code end
  if not unicode(path)then return open(path,mode)end
  return scoped('open',open,path,mode)
 end
 function fs.remove(path)
  local ok,e,code=valid_path(path);if not ok then return nil,e,code end
  if not unicode(path)then return remove(path)end
  return scoped('remove',remove,path)
 end
 function fs.rename(from,to)
  for _,path in ipairs({from,to})do
   local ok,e,code=valid_path(path);if not ok then return nil,e,code end
  end
  if not unicode(from)and not unicode(to)then return rename(from,to)end
  return scoped('rename',rename,from,to)
 end
 return fs
end
local default=M.new()
M.open,M.remove,M.rename=default.open,default.remove,default.rename
return M
