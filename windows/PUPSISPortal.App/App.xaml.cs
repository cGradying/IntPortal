using Microsoft.UI.Xaml;
using PUPSISPortal.App.Platform;

namespace PUPSISPortal.App;

public partial class App : Application
{
    private Window? _window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        ToastReminders.Register();
        _window = new MainWindow();
        _window.Activate();
    }
}
