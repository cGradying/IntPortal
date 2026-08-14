using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using PUPSISPortal.Core;

namespace PUPSISPortal.App.Views;

/// <summary>
/// The Grades screen — the WinUI counterpart of macOS's GradesView.swift.
/// Summary (computed GPA, posted count), a GPA trend across terms, units
/// completed, a term picker, and the subject rows.
///
/// The trend only plots terms already in the local <see cref="GradesStore"/>
/// history, folded in automatically as each grades refresh posts (see
/// <c>SisSession.LoadGradesCore</c>). The mac app's "Load past terms" button
/// drives a term-by-term SIS re-scrape that Core's Windows session doesn't
/// implement yet (ponytail in SisSession.cs: needs an eval-and-await-navigation
/// primitive the 2-method ISisWebView interface doesn't expose) — so there's no
/// backfill button here; the trend just grows as the term goes on.
/// </summary>
public sealed class GradesView : UserControl
{
    private readonly StackPanel _content = new() { Spacing = 16, Padding = new Thickness(20), MaxWidth = 720 };
    private readonly ScrollViewer _scroll;
    private readonly TextBlock _empty = new()
    {
        Text = "No grades yet.", HorizontalAlignment = HorizontalAlignment.Center,
        Margin = new Thickness(40), Opacity = 0.6,
    };

    private List<GradeReport> _terms = new();
    private string? _selectedTerm;

    public GradesView()
    {
        _scroll = new ScrollViewer { Content = _content, HorizontalAlignment = HorizontalAlignment.Center };
        var root = new Grid();
        root.Children.Add(_scroll);
        root.Children.Add(_empty);
        Content = root;
    }

    /// Refreshes from the session's current report (loading it first if needed)
    /// plus whatever term history is cached, and re-renders.
    public async Task LoadAsync(SisSession session)
    {
        if (session.Grades is null)
            await session.LoadGradesAsync();

        var history = GradesStore.LoadHistory();
        _terms = session.Grades is { } current
            ? GradesStore.Merged(current, history)
            : history;

        _selectedTerm ??= session.Grades?.TermLabel ?? _terms.LastOrDefault()?.TermLabel;
        Render();
    }

    private void Render()
    {
        _content.Children.Clear();
        var shown = _terms.FirstOrDefault(t => t.TermLabel == _selectedTerm) ?? _terms.LastOrDefault();

        _empty.Visibility = shown is null || shown.Subjects.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        _scroll.Visibility = _empty.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
        if (shown is null) return;

        var trendTerms = _terms.Where(t => t.ComputedGpa.HasValue).ToList();
        if (trendTerms.Count >= 2) _content.Children.Add(TrendCard(trendTerms));
        _content.Children.Add(UnitsCard());
        if (_terms.Count > 1) _content.Children.Add(TermPicker());
        _content.Children.Add(SummaryCard(shown));
        _content.Children.Add(SubjectList(shown));
    }

    // MARK: Trend

    private FrameworkElement TrendCard(List<GradeReport> terms)
    {
        const double height = 160, padLeft = 40, padRight = 8, padTop = 8, padBottom = 20;
        var canvas = new Canvas { Height = height };
        canvas.SizeChanged += (_, _) => DrawTrend(canvas, terms, padLeft, padRight, padTop, padBottom);

        var card = new StackPanel { Spacing = 10 };
        card.Children.Add(Header("GPA trend"));
        card.Children.Add(canvas);
        return Card(card);
    }

    private static void DrawTrend(Canvas canvas, List<GradeReport> terms, double padLeft, double padRight, double padTop, double padBottom)
    {
        canvas.Children.Clear();
        var w = canvas.ActualWidth;
        var h = canvas.ActualHeight;
        if (w <= 0 || h <= 0) return;

        var plotW = w - padLeft - padRight;
        var plotH = h - padTop - padBottom;
        var gridBrush = new SolidColorBrush(Color.FromArgb(60, 128, 128, 128));
        var lineBrush = new SolidColorBrush(Colors.SteelBlue);

        // PUP grades run 1.00 (best) to 5.00 (worst); flip so "up" reads as
        // improving — GPA 1.0 maps to the top of the plot, 5.0 to the bottom.
        double Y(double gpa) => padTop + (gpa - 1.0) / 4.0 * plotH;
        double X(int index) => terms.Count <= 1 ? padLeft : padLeft + plotW * index / (terms.Count - 1.0);

        for (var mark = 1; mark <= 5; mark++)
        {
            var y = Y(mark);
            canvas.Children.Add(new Line { X1 = padLeft, Y1 = y, X2 = w - padRight, Y2 = y, Stroke = gridBrush, StrokeThickness = 1 });
            var label = new TextBlock { Text = mark.ToString("0.00"), FontSize = 10, Opacity = 0.6 };
            Canvas.SetLeft(label, 0);
            Canvas.SetTop(label, y - 7);
            canvas.Children.Add(label);
        }

        var points = new PointCollection();
        for (var i = 0; i < terms.Count; i++)
        {
            var gpa = terms[i].ComputedGpa!.Value;
            var (x, y) = (X(i), Y(gpa));
            points.Add(new Windows.Foundation.Point(x, y));

            var dot = new Ellipse { Width = 6, Height = 6, Fill = lineBrush };
            Canvas.SetLeft(dot, x - 3);
            Canvas.SetTop(dot, y - 3);
            canvas.Children.Add(dot);
        }
        canvas.Children.Add(new Polyline { Points = points, Stroke = lineBrush, StrokeThickness = 2 });
    }

    // MARK: Summary / units / picker / rows

    private FrameworkElement SummaryCard(GradeReport report)
    {
        var posted = report.Subjects.Count(s => s.IsPosted);
        var total = report.Subjects.Count;

        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 24 };

        var gpaCol = new StackPanel { Spacing = 4 };
        gpaCol.Children.Add(Header("GPA"));
        gpaCol.Children.Add(new TextBlock
        {
            Text = report.ComputedGpa is { } gpa ? gpa.ToString("0.00") : "—",
            FontSize = 30, FontWeight = FontWeights.SemiBold,
        });
        gpaCol.Children.Add(new TextBlock
        {
            Text = posted == 0 ? "No grades posted yet" : $"{posted} of {total} subject{(total == 1 ? "" : "s")} posted",
            FontSize = 12, Opacity = 0.6,
        });
        row.Children.Add(gpaCol);

        return Card(row);
    }

    private FrameworkElement UnitsCard()
    {
        // ponytail: no retake dedup — a repeated subject counts twice; revisit
        // if that ever matters (mirrors the mac app's same shortcut).
        var completed = _terms.Sum(t => t.CompletedUnits);

        var col = new StackPanel { Spacing = 8 };
        col.Children.Add(Header("Units completed"));
        col.Children.Add(new TextBlock
        {
            Text = completed.ToString(completed % 1 == 0 ? "0" : "0.0"),
            FontSize = 18, FontWeight = FontWeights.SemiBold,
        });
        return Card(col);
    }

    private FrameworkElement TermPicker()
    {
        var combo = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var term in Enumerable.Reverse(_terms))
            combo.Items.Add(term.TermLabel);
        combo.SelectedItem = _selectedTerm;
        combo.SelectionChanged += (_, _) =>
        {
            if (combo.SelectedItem is string label && label != _selectedTerm)
            {
                _selectedTerm = label;
                Render();
            }
        };
        return combo;
    }

    private static FrameworkElement SubjectList(GradeReport report)
    {
        var list = new StackPanel { Spacing = 8 };
        foreach (var subject in report.Subjects)
        {
            var row = new Grid { Padding = new Thickness(12) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var left = new StackPanel { Spacing = 2 };
            left.Children.Add(new TextBlock { Text = subject.SubjectCode, FontWeight = FontWeights.SemiBold });
            left.Children.Add(new TextBlock { Text = subject.Description, FontSize = 12, Opacity = 0.6 });
            Grid.SetColumn(left, 0);

            var grade = new TextBlock
            {
                Text = string.IsNullOrEmpty(subject.FinalGrade) ? "—" : subject.FinalGrade,
                FontSize = 16, FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(grade, 1);

            row.Children.Add(left);
            row.Children.Add(grade);

            list.Children.Add(new Border
            {
                Child = row,
                Background = new SolidColorBrush(Color.FromArgb(18, 128, 128, 128)),
                CornerRadius = new CornerRadius(10),
            });
        }
        return list;
    }

    // MARK: Chrome

    private static TextBlock Header(string text) => new() { Text = text, FontSize = 12, Opacity = 0.6 };

    private static Border Card(FrameworkElement content) => new()
    {
        Child = content,
        Padding = new Thickness(18),
        CornerRadius = new CornerRadius(16),
        Background = new SolidColorBrush(Color.FromArgb(14, 128, 128, 128)),
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };
}
