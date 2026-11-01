using System;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AntOverhaulInstaller
{
    internal sealed class LogWindow : Window
    {
        private readonly TextBox _log;
        internal LogWindow()
        {
            Title = "蚂蚁大修 — 执行详情"; Width = 820; Height = 560; MinWidth = 620; MinHeight = 420;
            WindowStartupLocation = WindowStartupLocation.CenterOwner; Background = new SolidColorBrush(Color.FromRgb(14,14,16));
            FontFamily = new FontFamily("Microsoft YaHei UI");
            Grid root = new Grid { Margin = new Thickness(22) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.Children.Add(new TextBlock { Text = "执行详情", FontSize = 24, FontWeight = FontWeights.Bold, Foreground = Brushes.White, Margin = new Thickness(0,0,0,14) });
            _log = new TextBox { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = new SolidColorBrush(Color.FromRgb(25,25,29)),
                Foreground = new SolidColorBrush(Color.FromRgb(225,225,225)), BorderBrush = new SolidColorBrush(Color.FromRgb(70,70,78)),
                Padding = new Thickness(12), FontFamily = new FontFamily("Consolas, Microsoft YaHei UI"), FontSize = 13 };
            Grid.SetRow(_log,1); root.Children.Add(_log);
            StackPanel buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0,14,0,0) };
            buttons.Children.Add(Button("复制全部", delegate { try { Clipboard.SetText(_log.Text ?? ""); } catch (Exception e) { MessageBox.Show(this,e.Message,"无法复制"); } }));
            buttons.Children.Add(Button("保存日志", delegate { SaveLog(); }));
            buttons.Children.Add(Button("关闭", delegate { Hide(); }));
            Grid.SetRow(buttons,2); root.Children.Add(buttons); Content = root;
            Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e) { e.Cancel = true; Hide(); };
        }
        private Button Button(string title, RoutedEventHandler action)
        {
            AnimatedButton button = new AnimatedButton(Color.FromRgb(35,35,39),Color.FromRgb(53,53,60),Color.FromRgb(25,25,28),6)
                { Content = title, Foreground = Brushes.White, Width = 104, Height = 34, Margin = new Thickness(8,0,0,0) };
            button.Click += action; return button;
        }
        internal void Append(string line)
        {
            if (!Dispatcher.CheckAccess()) { Dispatcher.BeginInvoke(new Action<string>(Append),line); return; }
            _log.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + line + Environment.NewLine); _log.ScrollToEnd();
        }
        private void SaveLog()
        {
            Microsoft.Win32.SaveFileDialog dialog = new Microsoft.Win32.SaveFileDialog { FileName = "蚂蚁大修-安装日志.txt", Filter = "文本文件|*.txt", DefaultExt = ".txt" };
            if (dialog.ShowDialog(this) == true) { try { File.WriteAllText(dialog.FileName,_log.Text,new UTF8Encoding(true)); } catch(Exception ex) { MessageBox.Show(this,ex.Message,"无法保存日志"); } }
        }
        internal static void Snapshot(FrameworkElement element, string path)
        {
            element.UpdateLayout();
            RenderTargetBitmap bitmap = new RenderTargetBitmap(Math.Max(1,(int)Math.Ceiling(element.ActualWidth)),Math.Max(1,(int)Math.Ceiling(element.ActualHeight)),96,96,PixelFormats.Pbgra32);
            bitmap.Render(element); PngBitmapEncoder encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            string absolute = Path.GetFullPath(path); Directory.CreateDirectory(Path.GetDirectoryName(absolute));
            using (FileStream stream = new FileStream(absolute,FileMode.Create,FileAccess.Write,FileShare.None)) encoder.Save(stream);
        }
    }
}
