using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace AntOverhaulInstaller
{
    internal sealed class AnimatedButton : Button
    {
        private readonly Color _normal;
        private readonly Color _hover;
        private readonly Color _pressed;
        private readonly ScaleTransform _scale;
        private readonly TranslateTransform _translate;

        public AnimatedButton(Color normal, Color hover, Color pressed, double cornerRadius)
        {
            _normal = normal;
            _hover = hover;
            _pressed = pressed;
            Cursor = Cursors.Hand;
            Background = new SolidColorBrush(_normal);
            BorderThickness = new Thickness(0);
            RenderTransformOrigin = new Point(0.5, 0.5);
            _scale = new ScaleTransform(1, 1);
            _translate = new TranslateTransform(0, 0);
            TransformGroup transforms = new TransformGroup();
            transforms.Children.Add(_scale);
            transforms.Children.Add(_translate);
            RenderTransform = transforms;

            FrameworkElementFactory border = new FrameworkElementFactory(typeof(Border));
            border.SetValue(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
            border.SetValue(Border.BorderBrushProperty, new System.Windows.Data.Binding("BorderBrush") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
            border.SetValue(Border.BorderThicknessProperty, new System.Windows.Data.Binding("BorderThickness") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
            border.SetValue(Border.CornerRadiusProperty, new CornerRadius(cornerRadius));
            FrameworkElementFactory presenter = new FrameworkElementFactory(typeof(ContentPresenter));
            presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            presenter.SetValue(ContentPresenter.RecognizesAccessKeyProperty, true);
            border.AppendChild(presenter);
            Template = new ControlTemplate(typeof(Button)) { VisualTree = border };
            IsEnabledChanged += delegate
            {
                Opacity = IsEnabled ? 1.0 : 0.42;
                Cursor = IsEnabled ? Cursors.Hand : Cursors.Arrow;
                if (!IsEnabled) AnimateRelease(_normal);
            };
        }

        protected override void OnMouseEnter(MouseEventArgs e)
        {
            base.OnMouseEnter(e);
            if (IsEnabled) AnimateColor(_hover, 130);
        }

        protected override void OnMouseLeave(MouseEventArgs e)
        {
            base.OnMouseLeave(e);
            if (IsEnabled) AnimateRelease(_normal);
        }

        protected override void OnPreviewMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            base.OnPreviewMouseLeftButtonDown(e);
            if (!IsEnabled) return;
            AnimateColor(_pressed, 70);
            AnimateTransform(0.97, 2.0, 70);
        }

        protected override void OnPreviewMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            base.OnPreviewMouseLeftButtonUp(e);
            if (!IsEnabled) return;
            AnimateRelease(IsMouseOver ? _hover : _normal);
        }

        private void AnimateRelease(Color color)
        {
            AnimateColor(color, 120);
            AnimateTransform(1.0, 0.0, 120);
        }

        private void AnimateTransform(double scale, double y, int milliseconds)
        {
            Duration duration = TimeSpan.FromMilliseconds(milliseconds);
            _scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(scale, duration));
            _scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(scale, duration));
            _translate.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(y, duration));
        }

        private void AnimateColor(Color target, int milliseconds)
        {
            SolidColorBrush brush = Background as SolidColorBrush;
            if (brush == null || brush.IsFrozen)
            {
                brush = new SolidColorBrush(_normal);
                Background = brush;
            }
            brush.BeginAnimation(SolidColorBrush.ColorProperty, new ColorAnimation(target, TimeSpan.FromMilliseconds(milliseconds)));
        }
    }
}

