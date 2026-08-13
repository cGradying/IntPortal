using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace PUPSISPortal.Core;

/// <summary>
/// Portable preferences data model. Persists via JsonStore to a JSON file
/// so it can be loaded/tested without platform-specific UserDefaults.
/// </summary>
public class PreferencesData
{
    [JsonPropertyName("theme")]
    public string Theme { get; set; } = "auto";

    [JsonPropertyName("subjectColors")]
    public Dictionary<string, string> SubjectColors { get; set; } = new();

    [JsonPropertyName("termStatuses")]
    public Dictionary<string, SessionStatus> TermStatuses { get; set; } = new();

    [JsonPropertyName("occurrenceStatuses")]
    public Dictionary<string, SessionStatus> OccurrenceStatuses { get; set; } = new();

    [JsonPropertyName("onlineStripColors")]
    public Dictionary<string, string> OnlineStripColors { get; set; } = new();

    [JsonPropertyName("eventColors")]
    public Dictionary<string, string> EventColors { get; set; } = new();

    [JsonPropertyName("visibleCalendarIDs")]
    public List<string> VisibleCalendarIds { get; set; } = new();

    [JsonPropertyName("exportCalendarID")]
    public string ExportCalendarId { get; set; } = "";

    [JsonPropertyName("onlineExportCalendarID")]
    public string OnlineExportCalendarId { get; set; } = "";

    [JsonPropertyName("termEndDate")]
    public long TermEndDateTicks { get; set; } = 0;

    [JsonPropertyName("notificationsEnabled")]
    public bool NotificationsEnabled { get; set; } = false;

    [JsonPropertyName("notificationLeadMinutes")]
    public int NotificationLeadMinutes { get; set; } = 15;

    [JsonPropertyName("programTotalUnits")]
    public int ProgramTotalUnits { get; set; } = 0;

    [JsonPropertyName("googleClientID")]
    public string GoogleClientId { get; set; } = "";

    [JsonPropertyName("googleCalendarID")]
    public string GoogleCalendarId { get; set; } = "";

    [JsonPropertyName("islandStartHome")]
    public bool IslandStartHome { get; set; } = true;

    [JsonPropertyName("islandExpandOnHover")]
    public bool IslandExpandOnHover { get; set; } = true;

    [JsonPropertyName("trafficLightsAutoHide")]
    public bool TrafficLightsAutoHide { get; set; } = true;
}

/// <summary>
/// User preferences with INotifyPropertyChanged for WinUI binding.
/// Backed by a JSON file (via JsonStore) instead of UserDefaults.
/// </summary>
public class Preferences : INotifyPropertyChanged
{
    private const string PreferencesFilename = "preferences.json";
    private readonly string? _customDirectory;
    private PreferencesData _data;

    public event PropertyChangedEventHandler? PropertyChanged;

    private ThemeChoice _theme;
    private Dictionary<string, string> _subjectColors;
    private Dictionary<string, SessionStatus> _termStatuses;
    private Dictionary<string, SessionStatus> _occurrenceStatuses;
    private Dictionary<string, string> _onlineStripColors;
    private Dictionary<string, string> _eventColors;
    private HashSet<string> _visibleCalendarIds;
    private string _exportCalendarId;
    private string _onlineExportCalendarId;
    private DateTime _termEndDate;
    private bool _notificationsEnabled;
    private int _notificationLeadMinutes;
    private int _programTotalUnits;
    private string _googleClientId;
    private string _googleCalendarId;
    private bool _islandStartHome;
    private bool _islandExpandOnHover;
    private bool _trafficLightsAutoHide;

    public static int[] LeadOptions => new[] { 5, 10, 15, 30 };

    public ThemeChoice Theme
    {
        get => _theme;
        set
        {
            if (_theme != value)
            {
                _theme = value;
                _data.Theme = value switch
                {
                    ThemeChoice.Auto => "auto",
                    ThemeChoice.PupMaroon => "pupMaroon",
                    ThemeChoice.AstraMoon => "astraMoon",
                    _ => "auto",
                };
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Subject code → hex. Absent means "use the palette's default".
    /// </summary>
    public Dictionary<string, string> SubjectColors
    {
        get => _subjectColors;
        private set
        {
            if (_subjectColors != value)
            {
                _subjectColors = value;
                _data.SubjectColors = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// The term-wide default status per meeting, keyed by `ClassSession.Id`.
    /// </summary>
    public Dictionary<string, SessionStatus> TermStatuses
    {
        get => _termStatuses;
        private set
        {
            if (_termStatuses != value)
            {
                _termStatuses = value;
                _data.TermStatuses = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// This-week exceptions to the term default.
    /// </summary>
    public Dictionary<string, SessionStatus> OccurrenceStatuses
    {
        get => _occurrenceStatuses;
        private set
        {
            if (_occurrenceStatuses != value)
            {
                _occurrenceStatuses = value;
                _data.OccurrenceStatuses = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Per-subject colour of the strip drawn around an online class.
    /// </summary>
    public Dictionary<string, string> OnlineStripColors
    {
        get => _onlineStripColors;
        private set
        {
            if (_onlineStripColors != value)
            {
                _onlineStripColors = value;
                _data.OnlineStripColors = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Event colours, keyed by `DayBlock.groupKey`.
    /// </summary>
    public Dictionary<string, string> EventColors
    {
        get => _eventColors;
        private set
        {
            if (_eventColors != value)
            {
                _eventColors = value;
                _data.EventColors = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Which Calendar.app calendars are drawn in the grid.
    /// </summary>
    public HashSet<string> VisibleCalendarIds
    {
        get => _visibleCalendarIds;
        set
        {
            if (!_visibleCalendarIds.SetEquals(value))
            {
                _visibleCalendarIds = value;
                _data.VisibleCalendarIds = value.ToList();
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Which calendar in-person classes get exported into.
    /// </summary>
    public string ExportCalendarId
    {
        get => _exportCalendarId;
        set
        {
            if (_exportCalendarId != value)
            {
                _exportCalendarId = value;
                _data.ExportCalendarId = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Which calendar online classes go into.
    /// </summary>
    public string OnlineExportCalendarId
    {
        get => _onlineExportCalendarId;
        set
        {
            if (_onlineExportCalendarId != value)
            {
                _onlineExportCalendarId = value;
                _data.OnlineExportCalendarId = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// When exported classes stop repeating.
    /// </summary>
    public DateTime TermEndDate
    {
        get => _termEndDate;
        set
        {
            if (_termEndDate != value)
            {
                _termEndDate = value;
                _data.TermEndDateTicks = value.Ticks;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Notifications enabled?
    /// </summary>
    public bool NotificationsEnabled
    {
        get => _notificationsEnabled;
        set
        {
            if (_notificationsEnabled != value)
            {
                _notificationsEnabled = value;
                _data.NotificationsEnabled = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Minutes before a class starts.
    /// </summary>
    public int NotificationLeadMinutes
    {
        get => _notificationLeadMinutes;
        set
        {
            if (_notificationLeadMinutes != value)
            {
                _notificationLeadMinutes = value;
                _data.NotificationLeadMinutes = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// The program's total required units.
    /// </summary>
    public int ProgramTotalUnits
    {
        get => _programTotalUnits;
        set
        {
            if (_programTotalUnits != value)
            {
                _programTotalUnits = value;
                _data.ProgramTotalUnits = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// The user's own Google OAuth client ID.
    /// </summary>
    public string GoogleClientId
    {
        get => _googleClientId;
        set
        {
            if (_googleClientId != value)
            {
                _googleClientId = value;
                _data.GoogleClientId = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Which Google calendar classes export into.
    /// </summary>
    public string GoogleCalendarId
    {
        get => _googleCalendarId;
        set
        {
            if (_googleCalendarId != value)
            {
                _googleCalendarId = value;
                _data.GoogleCalendarId = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Island starts on home launcher.
    /// </summary>
    public bool IslandStartHome
    {
        get => _islandStartHome;
        set
        {
            if (_islandStartHome != value)
            {
                _islandStartHome = value;
                _data.IslandStartHome = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Island expands on hover.
    /// </summary>
    public bool IslandExpandOnHover
    {
        get => _islandExpandOnHover;
        set
        {
            if (_islandExpandOnHover != value)
            {
                _islandExpandOnHover = value;
                _data.IslandExpandOnHover = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Traffic lights auto-hide.
    /// </summary>
    public bool TrafficLightsAutoHide
    {
        get => _trafficLightsAutoHide;
        set
        {
            if (_trafficLightsAutoHide != value)
            {
                _trafficLightsAutoHide = value;
                _data.TrafficLightsAutoHide = value;
                Save();
                OnPropertyChanged();
            }
        }
    }

    public Preferences(string? customDirectory = null)
    {
        _customDirectory = customDirectory;
        _data = Load();

        // Initialize from loaded data
        _theme = _data.Theme switch
        {
            "auto" => ThemeChoice.Auto,
            "pupMaroon" => ThemeChoice.PupMaroon,
            "astraMoon" => ThemeChoice.AstraMoon,
            _ => ThemeChoice.Auto,
        };
        _subjectColors = new Dictionary<string, string>(_data.SubjectColors);
        _termStatuses = new Dictionary<string, SessionStatus>(_data.TermStatuses);
        _occurrenceStatuses = new Dictionary<string, SessionStatus>(_data.OccurrenceStatuses);
        _onlineStripColors = new Dictionary<string, string>(_data.OnlineStripColors);
        _eventColors = new Dictionary<string, string>(_data.EventColors);
        _visibleCalendarIds = new HashSet<string>(_data.VisibleCalendarIds);
        _exportCalendarId = _data.ExportCalendarId;
        _onlineExportCalendarId = _data.OnlineExportCalendarId;
        _termEndDate = _data.TermEndDateTicks == 0 ? DefaultTermEnd() : new DateTime(_data.TermEndDateTicks);
        _notificationsEnabled = _data.NotificationsEnabled;
        _notificationLeadMinutes = _data.NotificationLeadMinutes;
        _programTotalUnits = _data.ProgramTotalUnits;
        _googleClientId = _data.GoogleClientId;
        _googleCalendarId = _data.GoogleCalendarId;
        _islandStartHome = _data.IslandStartHome;
        _islandExpandOnHover = _data.IslandExpandOnHover;
        _trafficLightsAutoHide = _data.TrafficLightsAutoHide;
    }

    /// <summary>
    /// Meetings marked vacant for the whole term.
    /// </summary>
    public HashSet<string> VacantSessionIds
    {
        get
        {
            var vacant = new HashSet<string>();
            foreach (var (id, status) in _termStatuses)
            {
                if (status == SessionStatus.Vacant)
                    vacant.Add(id);
            }
            return vacant;
        }
    }

    /// <summary>
    /// Far enough out to cover a semester, close enough that it's obviously a
    /// guess worth correcting.
    /// </summary>
    public static DateTime DefaultTermEnd()
    {
        return DateTime.Now.AddMonths(4).Date;
    }

    // Color methods

    public string ColorForEvent(string groupKey)
    {
        if (_eventColors.TryGetValue(groupKey, out var hex))
            return hex;
        return "";
    }

    public void SetEventColor(string groupKey, string hex)
    {
        _eventColors[groupKey] = hex;
        _data.EventColors = _eventColors;
        Save();
        OnPropertyChanged(nameof(EventColors));
    }

    public void ResetEventColor(string groupKey)
    {
        if (_eventColors.Remove(groupKey))
        {
            _data.EventColors = _eventColors;
            Save();
            OnPropertyChanged(nameof(EventColors));
        }
    }

    public bool HasCustomEventColor(string groupKey) => _eventColors.ContainsKey(groupKey);

    // Calendar methods

    public void SetCalendarVisible(string id, bool visible)
    {
        if (visible)
        {
            _visibleCalendarIds.Add(id);
        }
        else
        {
            _visibleCalendarIds.Remove(id);
        }
        _data.VisibleCalendarIds = _visibleCalendarIds.ToList();
        Save();
        OnPropertyChanged(nameof(VisibleCalendarIds));
    }

    // Status methods

    private string OccurrenceKey(string sessionId, DateTime weekStart)
    {
        return $"{sessionId}@{(long)(weekStart - DateTime.UnixEpoch).TotalSeconds}";
    }

    /// <summary>
    /// The status a meeting shows in a given week: this week's exception if
    /// there is one, otherwise the term default, otherwise in person.
    /// </summary>
    public SessionStatus Status(string sessionId, DateTime weekStart)
    {
        var key = OccurrenceKey(sessionId, weekStart);
        if (_occurrenceStatuses.TryGetValue(key, out var status))
            return status;
        if (_termStatuses.TryGetValue(sessionId, out status))
            return status;
        return SessionStatus.Regular;
    }

    /// <summary>
    /// Set the status for this week.
    /// </summary>
    public void SetStatus(string sessionId, DateTime weekStart, SessionStatus status)
    {
        var key = OccurrenceKey(sessionId, weekStart);
        var baseStatus = _termStatuses.TryGetValue(sessionId, out var ts) ? ts : SessionStatus.Regular;

        if (status == baseStatus)
        {
            _occurrenceStatuses.Remove(key);
        }
        else
        {
            _occurrenceStatuses[key] = status;
        }

        _data.OccurrenceStatuses = _occurrenceStatuses;
        Save();
        OnPropertyChanged(nameof(OccurrenceStatuses));
    }

    /// <summary>
    /// Get the term-wide status for a session.
    /// </summary>
    public SessionStatus TermStatus(string sessionId)
    {
        return _termStatuses.TryGetValue(sessionId, out var status) ? status : SessionStatus.Regular;
    }

    /// <summary>
    /// Set the term-wide status.
    /// </summary>
    public void SetTermStatus(string sessionId, SessionStatus status)
    {
        if (status == SessionStatus.Regular)
        {
            _termStatuses.Remove(sessionId);
        }
        else
        {
            _termStatuses[sessionId] = status;
        }

        _data.TermStatuses = _termStatuses;
        Save();
        OnPropertyChanged(nameof(TermStatuses));
    }

    // Subject color methods

    public string ColorForSubject(string subjectCode)
    {
        return _subjectColors.TryGetValue(subjectCode, out var hex) ? hex : "";
    }

    public void SetSubjectColor(string subjectCode, string hex)
    {
        _subjectColors[subjectCode] = hex;
        _data.SubjectColors = _subjectColors;
        Save();
        OnPropertyChanged(nameof(SubjectColors));
    }

    public void ResetSubjectColor(string subjectCode)
    {
        if (_subjectColors.Remove(subjectCode))
        {
            _data.SubjectColors = _subjectColors;
            Save();
            OnPropertyChanged(nameof(SubjectColors));
        }
    }

    public bool HasCustomSubjectColor(string subjectCode) => _subjectColors.ContainsKey(subjectCode);

    // Online strip color methods

    public string StripColorForSubject(string subjectCode)
    {
        return _onlineStripColors.TryGetValue(subjectCode, out var hex) ? hex : "";
    }

    public void SetStripColor(string subjectCode, string hex)
    {
        _onlineStripColors[subjectCode] = hex;
        _data.OnlineStripColors = _onlineStripColors;
        Save();
        OnPropertyChanged(nameof(OnlineStripColors));
    }

    public void ResetStripColor(string subjectCode)
    {
        if (_onlineStripColors.Remove(subjectCode))
        {
            _data.OnlineStripColors = _onlineStripColors;
            Save();
            OnPropertyChanged(nameof(OnlineStripColors));
        }
    }

    public bool HasCustomStripColor(string subjectCode) => _onlineStripColors.ContainsKey(subjectCode);

    // Persistence

    private PreferencesData Load()
    {
        var loaded = JsonStore.Load<PreferencesData>(PreferencesFilename, _customDirectory);
        return loaded ?? new PreferencesData();
    }

    private void Save()
    {
        JsonStore.Save(_data, PreferencesFilename, _customDirectory);
    }

    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

/// <summary>
/// Theme choice enum with raw values matching the Swift version.
/// </summary>
public enum ThemeChoice
{
    Auto,
    PupMaroon,
    AstraMoon,
}

public static class ThemeChoiceExtensions
{
    public static string RawValue(this ThemeChoice choice) => choice switch
    {
        ThemeChoice.Auto => "auto",
        ThemeChoice.PupMaroon => "pupMaroon",
        ThemeChoice.AstraMoon => "astraMoon",
        _ => "auto",
    };

    public static ThemeChoice FromRawValue(string value) => value switch
    {
        "auto" => ThemeChoice.Auto,
        "pupMaroon" => ThemeChoice.PupMaroon,
        "astraMoon" => ThemeChoice.AstraMoon,
        _ => ThemeChoice.Auto,
    };
}
