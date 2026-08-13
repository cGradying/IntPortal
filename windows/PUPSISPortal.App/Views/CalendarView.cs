using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using PUPSISPortal.Core;

namespace PUPSISPortal.App.Views;

/// <summary>
/// The week grid — seven day columns, an hour gutter, and class blocks placed by
/// time. A minimal Stage-4 starting point drawn in code; the Liquid-Glass polish
/// of the macOS app is a later pass. Layout math is inline (kept independent of
/// Core's geometry API) so it's easy to reshape on Windows.
/// </summary>
public sealed class CalendarView : UserControl
{
    private static readonly string[] DayLabels = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    private const double Gutter = 48, HeaderH = 28, HourH = 44;
    private const int StartHour = 6, EndHour = 22; // 6am–10pm floor, like the mac app

    private readonly Canvas _canvas = new();
    private List<ClassSession> _sessions = new();

    public CalendarView()
    {
        Content = _canvas;
        _canvas.SizeChanged += (_, _) => Render();
    }

    public void Show(IEnumerable<ClassSession> sessions)
    {
        _sessions = sessions.ToList();
        Render();
    }

    private void Render()
    {
        _canvas.Children.Clear();
        double w = _canvas.ActualWidth, h = _canvas.ActualHeight;
        if (w <= 0 || h <= 0) return;

        double colW = (w - Gutter) / 7.0;
        double pxPerMin = HourH / 60.0;
        var gridBrush = new SolidColorBrush(Color.FromArgb(40, 128, 128, 128));

        // Hour rules + gutter labels.
        for (int hour = StartHour; hour <= EndHour; hour++)
        {
            double y = HeaderH + (hour - StartHour) * HourH;
            _canvas.Children.Add(Line(Gutter, y, w, y, gridBrush));
            var label = new TextBlock
            {
                Text = ClassSession.Format(hour * 60),
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromArgb(150, 128, 128, 128)),
            };
            Canvas.SetLeft(label, 6);
            Canvas.SetTop(label, y - 7);
            _canvas.Children.Add(label);
        }

        // Day headers + column separators.
        for (int day = 0; day < 7; day++)
        {
            double x = Gutter + day * colW;
            _canvas.Children.Add(Line(x, HeaderH, x, h, gridBrush));
            var head = new TextBlock { Text = DayLabels[day], FontSize = 12, FontWeight = FontWeights.SemiBold };
            Canvas.SetLeft(head, x + 6);
            Canvas.SetTop(head, 4);
            _canvas.Children.Add(head);
        }

        // Class blocks.
        foreach (var s in _sessions)
        {
            int col = (int)s.Day - 1; // Weekday.Monday == 1
            if (col < 0 || col > 6) continue;

            double top = HeaderH + (s.Start - StartHour * 60) * pxPerMin;
            double height = Math.Max((s.End - s.Start) * pxPerMin, 18);

            var block = new Border
            {
                Width = Math.Max(colW - 6, 0),
                Height = height,
                Background = new SolidColorBrush(SubjectColor(s.SubjectCode)),
                CornerRadius = new CornerRadius(6),
                Padding = new Thickness(6, 4, 6, 4),
                Child = new StackPanel
                {
                    Children =
                    {
                        new TextBlock { Text = s.SubjectCode, FontSize = 12, FontWeight = FontWeights.SemiBold,
                                        Foreground = new SolidColorBrush(Colors.White),
                                        TextTrimming = TextTrimming.CharacterEllipsis },
                        new TextBlock { Text = s.TimeLabel, FontSize = 10,
                                        Foreground = new SolidColorBrush(Color.FromArgb(220, 255, 255, 255)) },
                    },
                },
            };
            Canvas.SetLeft(block, Gutter + col * colW + 3);
            Canvas.SetTop(block, top);
            _canvas.Children.Add(block);
        }
    }

    private static Line Line(double x1, double y1, double x2, double y2, Brush stroke) =>
        new() { X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Stroke = stroke, StrokeThickness = 1 };

    /// <summary>
    /// A stable per-subject hue seeded from the code — deterministic across
    /// launches (never a per-process hash), matching the macOS app's rule.
    /// </summary>
    private static Color SubjectColor(string subjectCode)
    {
        int seed = 0;
        foreach (char c in subjectCode) seed = seed * 31 + c;
        double hue = (Math.Abs(seed) % 360);
        return FromHsl(hue, 0.55, 0.45);
    }

    private static Color FromHsl(double h, double s, double l)
    {
        double c = (1 - Math.Abs(2 * l - 1)) * s;
        double x = c * (1 - Math.Abs((h / 60.0) % 2 - 1));
        double m = l - c / 2;
        (double r, double g, double b) = h switch
        {
            < 60 => (c, x, 0.0),
            < 120 => (x, c, 0.0),
            < 180 => (0.0, c, x),
            < 240 => (0.0, x, c),
            < 300 => (x, 0.0, c),
            _ => (c, 0.0, x),
        };
        return Color.FromArgb(255,
            (byte)((r + m) * 255), (byte)((g + m) * 255), (byte)((b + m) * 255));
    }
}
