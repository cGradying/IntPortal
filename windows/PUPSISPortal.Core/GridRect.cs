namespace PUPSISPortal.Core;

/// <summary>
/// Double-precision rectangle for grid geometry. Replaces System.Drawing.RectangleF
/// to maintain precision parity with Swift's CGFloat math.
/// </summary>
public readonly record struct GridRect(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
}
