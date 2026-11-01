using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace AntOverhaulInstaller
{
    internal sealed class MainWindow : Window
    {
        private readonly BackendClient _backend;
        private readonly LogWindow _log = new LogWindow();
        private readonly TextBox _path;
        private readonly TextBlock _placeholder, _version, _state;
        private readonly Border _pathBorder;
        private readonly AnimatedButton _browse, _install, _uninstall, _details;
        private readonly ProgressBar _progress;
        private readonly DispatcherTimer _debounce;
        private readonly string _launchPath, _snapshot, _snapshotLog;
        private readonly bool _preview;
        private bool _busy, _inspecting, _settingPath, _loaded;
        private BackendResult _result;

        internal MainWindow(string launchPath, string saveGamesRoot, bool preview, string snapshot, string snapshotLog)
        {
            _backend = new BackendClient(saveGamesRoot);
            if (!string.IsNullOrWhiteSpace(saveGamesRoot)) _log.Append("自定义存档目录：" + saveGamesRoot);
            _launchPath = launchPath; _preview = preview; _snapshot = snapshot; _snapshotLog = snapshotLog;
            Title = "蚂蚁大修安装器"; Width = 720; Height = 720; MinWidth = 580; MinHeight = 580;
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; AllowsTransparency = true;
            Background = Brushes.Transparent; WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            Border shell = new Border { Background = Brushes.Black, CornerRadius = new CornerRadius(14), BorderBrush = Brush(34,34,38), BorderThickness = new Thickness(1), SnapsToDevicePixels = true };
            Canvas canvas = new Canvas { Width = 1080, Height = 1080, Background = Brushes.Black };
            Viewbox viewbox = new Viewbox { Stretch = Stretch.Uniform, Child = canvas }; shell.Child = viewbox; Content = shell;

            AnimatedButton minimize = Button("—", Color.FromRgb(14,14,14),Color.FromRgb(50,50,54),Color.FromRgb(30,30,33),42,34,20,7);
            minimize.Foreground = Brush(165,165,170); Place(canvas,minimize,972,18); minimize.ToolTip = "最小化";
            minimize.Click += delegate { WindowState = WindowState.Minimized; };
            AnimatedButton close = Button("×",Color.FromRgb(14,14,14),Color.FromRgb(145,45,52),Color.FromRgb(110,30,36),42,34,24,7);
            close.Foreground = Brush(190,190,195); Place(canvas,close,1020,18); close.ToolTip = "关闭"; close.Click += delegate { Close(); };

            Image logo = new Image { Source = LoadLogo("AntOverhaul.EotUSteamLogo.png"), Width = 650, Height = 365.625, Stretch = Stretch.Uniform, SnapsToDevicePixels = true };
            RenderOptions.SetBitmapScalingMode(logo,BitmapScalingMode.HighQuality);
            // Keep the original 640 x 360 canvas and its transparent margins intact.
            Place(canvas,logo,215,-18);
            System.Windows.Automation.AutomationProperties.SetName(logo,"Empires of the Undergrowth");
            TextBlock subtitle = Text("蚂蚁大修 · 模组安装器",28,Brush(116,239,190),FontWeights.SemiBold); subtitle.Width = 800; subtitle.TextAlignment = TextAlignment.Center;
            Place(canvas,subtitle,140,257);

            _pathBorder = new Border { Width = 655, Height = 58, Background = Brush(200,200,200), CornerRadius = new CornerRadius(9), BorderBrush = Brushes.Transparent, BorderThickness = new Thickness(3) };
            Grid pathGrid = new Grid(); _pathBorder.Child = pathGrid; Place(canvas,_pathBorder,135,306);
            _path = new TextBox { Background = Brushes.Transparent, Foreground = Brush(45,45,45), BorderThickness = new Thickness(0), FontSize = 27,
                Padding = new Thickness(10,5,10,3), VerticalContentAlignment = VerticalAlignment.Center, TabIndex = 0,
                ToolTip = "粘贴游戏根目录，按回车验证；也可以点击右侧浏览。" };
            _placeholder = Text("粘贴游戏根目录路径",27,Brush(105,105,105),FontWeights.Normal);
            _placeholder.Margin = new Thickness(12,7,0,0); _placeholder.IsHitTestVisible = false;
            pathGrid.Children.Add(_path); pathGrid.Children.Add(_placeholder);
            _browse = Button("浏览",Color.FromRgb(248,248,248),Color.FromRgb(255,255,255),Color.FromRgb(220,220,220),124,58,31,8);
            _browse.TabIndex = 1; _browse.ToolTip = "选择包含 EotU.exe 的游戏根目录"; Place(canvas,_browse,807,306);

            _install = Button("安装模组",Color.FromRgb(116,239,190),Color.FromRgb(137,250,207),Color.FromRgb(82,208,159),362,153,50,12);
            _install.FontWeight = FontWeights.Black; _install.IsEnabled = false; _install.TabIndex = 2; Place(canvas,_install,135,389);
            _uninstall = Button("卸载模组",Color.FromRgb(255,112,118),Color.FromRgb(255,133,139),Color.FromRgb(225,82,90),362,153,50,12);
            _uninstall.FontWeight = FontWeights.Black; _uninstall.IsEnabled = false; _uninstall.TabIndex = 3; Place(canvas,_uninstall,569,389);
            Place(canvas,Text("当前模组版本：",27,Brushes.White,FontWeights.Bold),136,579);
            _version = Text("v0.1.13",25,Brush(255,205,35),FontWeights.Bold); _version.Width = 795; Place(canvas,_version,136,623);
            StackPanel profile = new StackPanel { Orientation = Orientation.Horizontal };
            Image nexusIcon = new Image { Source = LoadLogo("AntOverhaul.NexusModsIcon.png"), Width = 30, Height = 30, Stretch = Stretch.Uniform, Margin = new Thickness(0,0,12,0), VerticalAlignment = VerticalAlignment.Center };
            RenderOptions.SetBitmapScalingMode(nexusIcon,BitmapScalingMode.HighQuality);
            System.Windows.Automation.AutomationProperties.SetName(nexusIcon,"Nexus Mods");
            TextBlock profileText = Text("",24,Brush(160,220,240),FontWeights.Normal);
            Hyperlink profileLink = new Hyperlink(new Run("nexusmods.com/profile/Miossstry")) {
                NavigateUri = new Uri("https://www.nexusmods.com/profile/Miossstry"),
                Foreground = Brush(160,220,240), Cursor = Cursors.Hand,
                ToolTip = "https://www.nexusmods.com/profile/Miossstry"
            };
            System.Windows.Automation.AutomationProperties.SetAutomationId(profileLink,"NexusProfileLink");
            System.Windows.Automation.AutomationProperties.SetName(profileLink,"Miossstry 的 Nexus Mods 主页");
            KeyboardNavigation.SetTabIndex(profileLink,4);
            profileLink.RequestNavigate += delegate(object sender, System.Windows.Navigation.RequestNavigateEventArgs e) {
                e.Handled = true;
                try { Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true }); }
                catch (Exception ex) { _log.Append("无法打开 Nexus Mods 主页："+ex.Message); Status("无法打开浏览器，请通过查看详情复制主页地址。",false); _log.Append(e.Uri.AbsoluteUri); }
            };
            profileText.Inlines.Add(profileLink); profile.Children.Add(nexusIcon); profile.Children.Add(profileText);
            Place(canvas,profile,136,678);

            _state = Text("正在寻找游戏目录…",22,Brush(180,180,185),FontWeights.SemiBold); _state.Width = 650; _state.Height = 72; _state.TextWrapping = TextWrapping.Wrap; _state.TextTrimming = TextTrimming.CharacterEllipsis;
            Place(canvas,_state,136,746);
            _details = Button("查看详情",Color.FromRgb(35,35,39),Color.FromRgb(53,53,60),Color.FromRgb(25,25,28),122,38,18,7);
            _details.Foreground = Brush(160,220,240); _details.TabIndex = 5; Place(canvas,_details,809,748);
            _progress = new ProgressBar { Width = 795, Height = 11, Minimum = 0, Maximum = 100, Background = Brush(38,38,42), Foreground = Brush(116,239,190), BorderThickness = new Thickness(0) };
            Place(canvas,_progress,136,829);

            System.Windows.Automation.AutomationProperties.SetAutomationId(_path,"GameRootPath");
            System.Windows.Automation.AutomationProperties.SetAutomationId(_browse,"BrowseGameRoot");
            System.Windows.Automation.AutomationProperties.SetAutomationId(_install,"InstallMod");
            System.Windows.Automation.AutomationProperties.SetAutomationId(_uninstall,"UninstallMod");
            System.Windows.Automation.AutomationProperties.SetAutomationId(_details,"ShowLog");
            System.Windows.Automation.AutomationProperties.SetAutomationId(_state,"StatusText");
            System.Windows.Automation.AutomationProperties.SetAutomationId(_version,"VersionText");

            _debounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(650) };
            _debounce.Tick += async delegate { _debounce.Stop(); if (!_preview) await InspectAsync(); };
            _path.TextChanged += delegate
            {
                _placeholder.Visibility = string.IsNullOrEmpty(_path.Text) ? Visibility.Visible : Visibility.Collapsed;
                if (_settingPath || !_loaded || _busy || _preview) return;
                _result = null; _install.IsEnabled = _uninstall.IsEnabled = false; _pathBorder.BorderBrush = Brushes.Transparent;
                _debounce.Stop(); _debounce.Start();
            };
            _path.PreviewKeyDown += async delegate(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { e.Handled = true; _debounce.Stop(); if (!_preview) await InspectAsync(); } };
            _browse.Click += async delegate { await BrowseAsync(); };
            _install.Click += async delegate { await ActAsync("Install"); };
            _uninstall.Click += async delegate { await ActAsync("Uninstall"); };
            _details.Click += delegate { ShowLog(); };
            MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e) { if (e.ButtonState == MouseButtonState.Pressed && e.GetPosition(this).Y < 60) DragMove(); };
            Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e)
            {
                if (_busy || _inspecting) { e.Cancel = true; Status("操作进行中，请完成后再关闭。",false); return; }
                _debounce.Stop();
            };
            Closed += delegate { _backend.Dispose(); };
            Loaded += OnLoaded;
        }

        private async void OnLoaded(object sender, RoutedEventArgs e)
        {
            double edge = Math.Max(580,Math.Min(720,Math.Min(SystemParameters.WorkArea.Width-30,SystemParameters.WorkArea.Height-30)));
            Width = Height = edge;
            if (_preview)
            {
                SetPath(@"D:\SteamLibrary\steamapps\common\Empires of the Undergrowth");
                Status("游戏目录已确认，可以安装。",true); _pathBorder.BorderBrush = Brush(75,204,145);
                _install.IsEnabled = true; _uninstall.IsEnabled = false; _loaded = true;
                _log.Append("界面预览模式：不会读取或修改正式游戏与存档。");
                _log.Append("安装器 v0.1.13；界面预览使用示例目录。");
                await TakeRequestedSnapshots(); return;
            }
            _browse.IsEnabled = _path.IsEnabled = false;
            try
            {
                string found = _launchPath;
                if (string.IsNullOrWhiteSpace(found)) found = await Task.Run(delegate { return SteamLocator.Find(); });
                if (!string.IsNullOrWhiteSpace(found)) SetPath(found);
            }
            catch (Exception ex) { _log.Append("自动查找目录失败："+ex.Message); }
            finally { _loaded = true; _browse.IsEnabled = _path.IsEnabled = true; }
            await InspectAsync();
            await TakeRequestedSnapshots();
        }

        private string InputPath() { return (_path.Text ?? "").Trim().Trim('"'); }
        private void SetPath(string value)
        {
            _settingPath = true;
            try { _path.Text = value ?? ""; _path.CaretIndex = 0; _path.ScrollToHome(); }
            finally { _settingPath = false; }
        }
        private async Task InspectAsync()
        {
            if (_busy || _inspecting || _preview) return;
            string requested = InputPath();
            _result = null; _install.IsEnabled = _uninstall.IsEnabled = false;
            if (string.IsNullOrWhiteSpace(requested))
            { Status("请选择游戏根目录，或粘贴路径后按回车。",false); return; }
            _inspecting = true; _progress.IsIndeterminate = true; Status("正在检查游戏目录和安装状态…",false);
            try
            {
                BackendResult result = await Task.Run(delegate { return _backend.Execute("Inspect",requested,_log.Append); });
                if (InputPath() != requested) return;
                _result = result;
                if (result.Success && !string.IsNullOrWhiteSpace(result.GameRoot)) SetPath(result.GameRoot);
                _install.Content = result.Installed ? "安装 / 更新" : "安装模组";
                _install.IsEnabled = result.CanInstall; _uninstall.IsEnabled = result.CanUninstall;
                _pathBorder.BorderBrush = result.Success ? Brush(75,204,145) : Brush(236,76,86);
                Status(result.Message,result.Success); _log.Append(result.Message);
            }
            catch (Exception ex) { if (InputPath() == requested) Failure(ex.Message); }
            finally
            {
                _inspecting = false; _progress.IsIndeterminate = false; _progress.Value = 0;
                if (InputPath() != requested && _result == null) { _debounce.Stop(); _debounce.Start(); }
            }
        }

        private async Task BrowseAsync()
        {
            if (_busy || _preview) return;
            using (System.Windows.Forms.FolderBrowserDialog dialog = new System.Windows.Forms.FolderBrowserDialog())
            {
                dialog.Description = "选择包含 EotU.exe 的《地下蚁国》游戏根目录";
                dialog.ShowNewFolderButton = false; dialog.SelectedPath = InputPath();
                if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK) { SetPath(dialog.SelectedPath); _debounce.Stop(); await InspectAsync(); }
            }
        }

        private async Task ActAsync(string action)
        {
            if (_preview || _busy || _inspecting || _result == null || !_result.Success) return;
            if (action == "Uninstall" && MessageBox.Show(this,
                "请先正常保存并退出游戏。\n\n安装器会自动备份并处理所有已加点殖民地的当前存档，然后卸载模组。无需进入游戏按 F6/F8，剧情进度和培养记录都会保留。\n\n现在卸载蚂蚁大修吗？", "卸载蚂蚁大修", MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No) != MessageBoxResult.Yes) return;
            string target = InputPath(); _busy = true; _debounce.Stop();
            _browse.IsEnabled = _path.IsEnabled = _install.IsEnabled = _uninstall.IsEnabled = false;
            _progress.IsIndeterminate = true;
            if (action == "Install") _install.Content = "正在安装…"; else _uninstall.Content = "正在卸载…";
            Status(action == "Install" ? "正在安装蚂蚁大修…" : "正在卸载蚂蚁大修…",false);
            _log.Append((action == "Install" ? "开始安装：" : "开始卸载：")+target);
            BackendResult completed = null;
            try
            {
                completed = await Task.Run(delegate { return _backend.Execute(action,target,_log.Append); });
                _result = completed;
                _log.Append(completed.Message); Status(completed.Message,completed.Success);
                if (!completed.Success) ShowLog();
            }
            catch (Exception ex) { Failure(ex.Message); ShowLog(); }
            finally
            {
                _busy = false; _progress.IsIndeterminate = false; _progress.Value = completed != null && completed.Success ? 100 : 0;
                _browse.IsEnabled = _path.IsEnabled = true;
                _install.Content = completed != null && completed.Success && action == "Install" ? "安装完成 ✓" : "安装模组";
                _uninstall.Content = completed != null && completed.Success && action == "Uninstall" ? "卸载完成 ✓" : "卸载模组";
                _install.IsEnabled = _result != null && _result.CanInstall;
                _uninstall.IsEnabled = _result != null && _result.CanUninstall;
            }
        }

        private async Task TakeRequestedSnapshots()
        {
            if (string.IsNullOrWhiteSpace(_snapshot) && string.IsNullOrWhiteSpace(_snapshotLog)) return;
            if (!string.IsNullOrWhiteSpace(_snapshotLog)) ShowLog();
            await Dispatcher.InvokeAsync(delegate
            {
                if (!string.IsNullOrWhiteSpace(_snapshot)) LogWindow.Snapshot(this,_snapshot);
                if (!string.IsNullOrWhiteSpace(_snapshotLog)) LogWindow.Snapshot(_log,_snapshotLog);
            },DispatcherPriority.ApplicationIdle);
            Close();
        }
        private void ShowLog() { if (_log.Owner == null) _log.Owner = this; if (!_log.IsVisible) _log.Show(); _log.Activate(); }
        private static BitmapImage LoadLogo(string resourceName)
        {
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
            {
                if (stream == null) throw new InvalidDataException("安装器缺少游戏徽标资源，请重新下载完整文件。");
                BitmapImage bitmap = new BitmapImage();
                bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze();
                return bitmap;
            }
        }
        private void Failure(string message) { _log.Append("操作失败："+message); _state.Text = message; _state.Foreground = Brush(255,112,118); _pathBorder.BorderBrush = Brush(236,76,86); }
        private void Status(string message,bool success) { _state.Text = message; _state.Foreground = success ? Brush(116,239,190) : Brush(180,180,185); _state.ToolTip = message; }
        private static SolidColorBrush Brush(byte r,byte g,byte b) { return new SolidColorBrush(Color.FromRgb(r,g,b)); }
        private static TextBlock Text(string value,double size,Brush color,FontWeight weight) { return new TextBlock { Text = value, FontSize = size, Foreground = color, FontWeight = weight }; }
        private static AnimatedButton Button(string label,Color normal,Color hover,Color pressed,double width,double height,double size,double corner)
        { return new AnimatedButton(normal,hover,pressed,corner) { Content = label, Foreground = Brushes.Black, Width = width, Height = height, FontSize = size, FontWeight = FontWeights.Medium }; }
        private static void Place(Canvas canvas,UIElement element,double x,double y) { Canvas.SetLeft(element,x); Canvas.SetTop(element,y); canvas.Children.Add(element); }
    }
}
