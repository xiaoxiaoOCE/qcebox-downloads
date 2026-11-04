using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;

[assembly: System.Reflection.AssemblyTitle("蚂蚁大修安装器")]
[assembly: System.Reflection.AssemblyDescription("地下蚁国 蚂蚁大修安装与卸载")]
[assembly: System.Reflection.AssemblyProduct("蚂蚁大修")]
[assembly: System.Reflection.AssemblyVersion("0.1.18.0")]
[assembly: System.Reflection.AssemblyFileVersion("0.1.18.0")]

namespace AntOverhaulInstaller
{
    internal static class Program
    {
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);

        [STAThread]
        private static int Main(string[] args)
        {
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
            string gameRoot = null, saveGamesRoot = null, snapshot = null, snapshotLog = null;
            bool preview = false;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--ui-test") preview = true;
                else if (args[i] == "--game-root" && i + 1 < args.Length) gameRoot = args[++i];
                else if (args[i] == "--save-games-root" && i + 1 < args.Length) saveGamesRoot = args[++i];
                else if (args[i] == "--snapshot" && i + 1 < args.Length) snapshot = args[++i];
                else if (args[i] == "--snapshot-log" && i + 1 < args.Length) snapshotLog = args[++i];
                else
                {
                    MessageBox.Show("无法识别的参数：" + args[i], "蚂蚁大修安装器", MessageBoxButton.OK, MessageBoxImage.Error);
                    return 2;
                }
            }
            bool created;
            using (Mutex mutex = new Mutex(true, @"Local\AntOverhaulInstaller", out created))
            {
                if (!created)
                {
                    MessageBox.Show("安装器已经在运行。", "蚂蚁大修安装器", MessageBoxButton.OK, MessageBoxImage.Information);
                    return 2;
                }
                try
                {
                    Application app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                    app.DispatcherUnhandledException += delegate(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
                    {
                        MessageBox.Show(e.Exception.Message, "蚂蚁大修安装器", MessageBoxButton.OK, MessageBoxImage.Error);
                        e.Handled = true;
                    };
                    MainWindow window = new MainWindow(gameRoot, saveGamesRoot, preview, snapshot, snapshotLog);
                    // LogWindow is constructed first; explicitly assign the real owner before Run.
                    app.MainWindow = window;
                    app.Run(window);
                    return 0;
                }
                catch (Exception ex)
                {
                    MessageBox.Show(ex.Message, "蚂蚁大修安装器", MessageBoxButton.OK, MessageBoxImage.Error);
                    return 1;
                }
            }
        }
    }
}
