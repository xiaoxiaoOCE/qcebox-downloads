using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace AntOverhaulInstaller
{
    internal sealed class BackendResult
    {
        internal bool Success, Installed, CanInstall, CanUninstall;
        internal string Message, Release, GameRoot, Status;
        internal string[] Details;
        private static string Text(Dictionary<string, object> values, string key)
        { object value; return values.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : ""; }
        private static bool Flag(Dictionary<string, object> values, string key, bool fallback)
        { object value; return values.TryGetValue(key, out value) && value is bool ? (bool)value : fallback; }
        internal static BackendResult Read(string path)
        {
            Dictionary<string, object> values = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(path, Encoding.UTF8));
            if (values == null || !values.ContainsKey("success")) throw new InvalidDataException("安装程序没有返回有效的操作结果。");
            BackendResult result = new BackendResult();
            result.Success = Flag(values, "success", false);
            result.Installed = Flag(values, "installed", false);
            result.Message = Text(values, "message");
            result.Release = Text(values, "release");
            result.GameRoot = Text(values, "gameRoot");
            result.Status = Text(values, "status");
            result.CanInstall = Flag(values, "canInstall", result.Success && !string.IsNullOrWhiteSpace(result.GameRoot));
            result.CanUninstall = Flag(values, "canUninstall", result.Success && result.Installed);
            List<string> details = new List<string>();
            object raw;
            if (values.TryGetValue("details", out raw) && raw != null)
            {
                System.Collections.IEnumerable lines = raw as System.Collections.IEnumerable;
                if (raw is string) details.Add((string)raw);
                else if (lines != null) foreach (object line in lines) details.Add(Convert.ToString(line));
                else details.Add(new JavaScriptSerializer().Serialize(raw));
            }
            result.Details = details.ToArray();
            return result;
        }
    }

    internal sealed class BackendClient : IDisposable
    {
        private string _directory;
        private readonly string _saveGamesRoot;
        private readonly string _temporaryBase = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "AntOverhaulInstaller"));

        internal BackendClient(string saveGamesRoot)
        {
            if (!string.IsNullOrWhiteSpace(saveGamesRoot))
            {
                if (!Path.IsPathRooted(saveGamesRoot) || Path.GetPathRoot(saveGamesRoot).Length < 3) throw new ArgumentException("自定义存档目录必须使用绝对路径。");
                _saveGamesRoot = Path.GetFullPath(saveGamesRoot);
            }
        }

        private string EnsurePayload()
        {
            if (_directory != null) return _directory;
            string target = Path.GetFullPath(Path.Combine(_temporaryBase, Guid.NewGuid().ToString("N")));
            if (!target.StartsWith(_temporaryBase + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new IOException("临时目录校验失败。");
            Directory.CreateDirectory(target);
            _directory = target;
            using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("AntOverhaul.Payload.zip"))
            {
                if (resource == null) throw new InvalidDataException("安装器载荷缺失，请重新下载完整安装器。");
                using (ZipArchive archive = new ZipArchive(resource, ZipArchiveMode.Read))
                {
                    HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        string name = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                        if (name.IndexOf(':') >= 0 || Path.IsPathRooted(name)) throw new InvalidDataException("安装载荷包含无效路径。");
                        string file = Path.GetFullPath(Path.Combine(target, name));
                        if (!file.StartsWith(target + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !seen.Add(file)) throw new InvalidDataException("安装载荷路径重复或越界。");
                        if (string.IsNullOrEmpty(entry.Name)) { Directory.CreateDirectory(file); continue; }
                        Directory.CreateDirectory(Path.GetDirectoryName(file));
                        using (Stream input = entry.Open())
                        using (FileStream output = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.None)) input.CopyTo(output);
                    }
                }
            }
            if (!File.Exists(Path.Combine(target, "Backend.ps1"))) throw new InvalidDataException("安装器缺少 Backend.ps1。");
            return target;
        }

        // Windows argv quoting only. The paths are never evaluated as PowerShell source or a shell command.
        internal static string Quote(string value)
        {
            StringBuilder result = new StringBuilder("\"");
            int slashes = 0;
            foreach (char c in value ?? "")
            {
                if (c == '\\') { slashes++; continue; }
                if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append('"'); }
                else { result.Append('\\', slashes); result.Append(c); }
                slashes = 0;
            }
            result.Append('\\', slashes * 2);
            return result.Append('"').ToString();
        }

        internal BackendResult Execute(string action, string gameRoot, Action<string> log)
        {
            if (action != "Inspect" && action != "Install" && action != "Uninstall") throw new ArgumentException("未知操作。");
            string package = EnsurePayload();
            string resultPath = Path.Combine(package, "result-" + Guid.NewGuid().ToString("N") + ".json");
            string executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(executable)) throw new FileNotFoundException("未找到 Windows PowerShell。");
            List<string> arguments = new List<string> { "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(package, "Backend.ps1"), "-Action", action, "-PackageRoot", package, "-ResultPath", resultPath };
            if (!string.IsNullOrWhiteSpace(gameRoot)) { arguments.Add("-GameRoot"); arguments.Add(gameRoot); }
            if (_saveGamesRoot != null) { arguments.Add("-SaveGamesRoot"); arguments.Add(_saveGamesRoot); }
            ProcessStartInfo start = new ProcessStartInfo(executable, string.Join(" ", arguments.ConvertAll(Quote).ToArray()))
            {
                WorkingDirectory = package, UseShellExecute = false, CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new IOException("无法启动安装程序。");
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                Task.WaitAll(output, error);
                if (!string.IsNullOrWhiteSpace(output.Result)) log(output.Result.Trim());
                if (!string.IsNullOrWhiteSpace(error.Result)) log(error.Result.Trim());
                if (!File.Exists(resultPath)) throw new IOException("操作未完成，安装程序没有生成结果。退出码：" + process.ExitCode + "。请查看详情。");
                BackendResult result = BackendResult.Read(resultPath);
                foreach (string line in result.Details) if (!string.IsNullOrWhiteSpace(line)) log(line);
                if (process.ExitCode != 0 && result.Success) throw new IOException("安装程序异常退出，未确认完成。退出码：" + process.ExitCode);
                return result;
            }
        }

        public void Dispose()
        {
            if (_directory == null) return;
            string full = Path.GetFullPath(_directory);
            string token = Path.GetFileName(full);
            Guid parsed;
            if (full.StartsWith(_temporaryBase + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) && Guid.TryParseExact(token, "N", out parsed))
            {
                try { if (Directory.Exists(full)) Directory.Delete(full, true); } catch { }
            }
            _directory = null;
        }
    }
}
