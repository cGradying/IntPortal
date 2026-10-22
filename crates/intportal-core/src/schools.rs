//! State universities and colleges listed in the portal hub before their
//! portals are built (spec 010 C13a). Each row is an id, a short name, the
//! school, its region and one base colour; the tile portal's ramp, accent,
//! shape and motif are derived from those, so a row is all a school needs.
//! The colours are placeholders until the universities reference confirms
//! each school's own.

/// (id, short name, school, region, base colour).
pub type Row = (&'static str, &'static str, &'static str, &'static str, &'static str);

pub const ROWS: &[Row] = &[
    ("earist", "EARIST", "Eulogio \"Amang\" Rodriguez Institute of Science and Technology", "NCR", "#c62828"),
    ("rtu", "RTU", "Rizal Technological University", "NCR", "#1e88e5"),
    ("philsca", "PhilSCA", "Philippine State College of Aeronautics", "NCR", "#5c6bc0"),
    ("mpc", "MPC", "Marikina Polytechnic College", "NCR", "#2e7d32"),
    ("bsu", "BSU", "Benguet State University", "CAR", "#43a047"),
    ("ksu", "KSU", "Kalinga State University", "CAR", "#d84315"),
    ("ifsu", "IfSU", "Ifugao State University", "CAR", "#7cb342"),
    ("asist", "ASIST", "Abra State Institute of Sciences and Technology", "CAR", "#00897b"),
    ("mpspc", "MPSPC", "Mountain Province State Polytechnic College", "CAR", "#6d4c41"),
    ("apayao", "ASC", "Apayao State College", "CAR", "#f9a825"),
    ("mmsu", "MMSU", "Mariano Marcos State University", "Ilocos", "#2e7d32"),
    ("unp", "UNP", "University of Northern Philippines", "Ilocos", "#8e24aa"),
    ("dmmmsu", "DMMMSU", "Don Mariano Marcos Memorial State University", "Ilocos", "#1b5e20"),
    ("psu", "PSU", "Pangasinan State University", "Ilocos", "#1565c0"),
    ("ispsc", "ISPSC", "Ilocos Sur Polytechnic State College", "Ilocos", "#ad1457"),
    ("csu", "CSU", "Cagayan State University", "Cagayan Valley", "#b71c1c"),
    ("isu", "ISU", "Isabela State University", "Cagayan Valley", "#388e3c"),
    ("nvsu", "NVSU", "Nueva Vizcaya State University", "Cagayan Valley", "#00838f"),
    ("qsu", "QSU", "Quirino State University", "Cagayan Valley", "#5e35b1"),
    ("bsc", "BSC", "Batanes State College", "Cagayan Valley", "#0277bd"),
    ("clsu", "CLSU", "Central Luzon State University", "Central Luzon", "#2e7d32"),
    ("bpsu", "BPSU", "Bataan Peninsula State University", "Central Luzon", "#1565c0"),
    ("neust", "NEUST", "Nueva Ecija University of Science and Technology", "Central Luzon", "#c62828"),
    ("tsu", "TSU", "Tarlac State University", "Central Luzon", "#e53935"),
    ("tau", "TAU", "Tarlac Agricultural University", "Central Luzon", "#558b2f"),
    ("prmsu", "PRMSU", "President Ramon Magsaysay State University", "Central Luzon", "#3949ab"),
    ("dhvsu", "DHVSU", "Don Honorio Ventura State University", "Central Luzon", "#8e1b1b"),
    ("ascot", "ASCOT", "Aurora State College of Technology", "Central Luzon", "#f57f17"),
    ("psau", "PSAU", "Pampanga State Agricultural University", "Central Luzon", "#43a047"),
    ("basc", "BASC", "Bulacan Agricultural State College", "Central Luzon", "#7cb342"),
    ("cvsu", "CvSU", "Cavite State University", "CALABARZON", "#2e7d32"),
    ("lspu", "LSPU", "Laguna State Polytechnic University", "CALABARZON", "#1565c0"),
    ("batstateu", "BatStateU", "Batangas State University", "CALABARZON", "#c62828"),
    ("slsu", "SLSU", "Southern Luzon State University", "CALABARZON", "#00897b"),
    ("urs", "URS", "University of Rizal System", "CALABARZON", "#1e88e5"),
    ("minsu", "MinSU", "Mindoro State University", "MIMAROPA", "#388e3c"),
    ("marsu", "MarSU", "Marinduque State University", "MIMAROPA", "#c2185b"),
    ("palsu", "PSU Palawan", "Palawan State University", "MIMAROPA", "#00838f"),
    ("wpu", "WPU", "Western Philippines University", "MIMAROPA", "#2e7d32"),
    ("rsu", "RSU", "Romblon State University", "MIMAROPA", "#1565c0"),
    ("omsc", "OMSC", "Occidental Mindoro State College", "MIMAROPA", "#f9a825"),
    ("bu", "BU", "Bicol University", "Bicol", "#ef6c00"),
    ("cbsua", "CBSUA", "Central Bicol State University of Agriculture", "Bicol", "#2e7d32"),
    ("cspc", "CSPC", "Camarines Sur Polytechnic Colleges", "Bicol", "#c62828"),
    ("cnsc", "CNSC", "Camarines Norte State College", "Bicol", "#1565c0"),
    ("sorsu", "SorSU", "Sorsogon State University", "Bicol", "#6a1b9a"),
    ("catsu", "CatSU", "Catanduanes State University", "Bicol", "#00838f"),
    ("parsu", "ParSU", "Partido State University", "Bicol", "#f57f17"),
    ("wvsu", "WVSU", "West Visayas State University", "Western Visayas", "#8e1b1b"),
    ("capsu", "CapSU", "Capiz State University", "Western Visayas", "#2e7d32"),
    ("isatu", "ISAT U", "Iloilo Science and Technology University", "Western Visayas", "#c62828"),
    ("cpsu", "CPSU", "Central Philippines State University", "Western Visayas", "#558b2f"),
    ("chmsu", "CHMSU", "Carlos Hilado Memorial State University", "Western Visayas", "#1565c0"),
    ("asu", "ASU", "Aklan State University", "Western Visayas", "#388e3c"),
    ("ua", "UA", "University of Antique", "Western Visayas", "#1e88e5"),
    ("gsu", "GSU", "Guimaras State University", "Western Visayas", "#00897b"),
    ("nonescost", "NONESCOST", "Northern Negros State College of Science and Technology", "Western Visayas", "#6a1b9a"),
    ("ctu", "CTU", "Cebu Technological University", "Central Visayas", "#f9a825"),
    ("norsu", "NORSU", "Negros Oriental State University", "Central Visayas", "#1565c0"),
    ("bisu", "BISU", "Bohol Island State University", "Central Visayas", "#2e7d32"),
    ("cnu", "CNU", "Cebu Normal University", "Central Visayas", "#c62828"),
    ("ssc", "SSC", "Siquijor State College", "Central Visayas", "#00838f"),
    ("lnu", "LNU", "Leyte Normal University", "Eastern Visayas", "#c62828"),
    ("evsu", "EVSU", "Eastern Visayas State University", "Eastern Visayas", "#8e1b1b"),
    ("vsu", "VSU", "Visayas State University", "Eastern Visayas", "#2e7d32"),
    ("ssu", "SSU", "Samar State University", "Eastern Visayas", "#1565c0"),
    ("essu", "ESSU", "Eastern Samar State University", "Eastern Visayas", "#43a047"),
    ("uep", "UEP", "University of Eastern Philippines", "Eastern Visayas", "#1b5e20"),
    ("nwssu", "NwSSU", "Northwest Samar State University", "Eastern Visayas", "#6a1b9a"),
    ("southleyte", "SLSU Leyte", "Southern Leyte State University", "Eastern Visayas", "#00897b"),
    ("bipsu", "BiPSU", "Biliran Province State University", "Eastern Visayas", "#0277bd"),
    ("wmsu", "WMSU", "Western Mindanao State University", "Zamboanga Peninsula", "#c62828"),
    ("jrmsu", "JRMSU", "Jose Rizal Memorial State University", "Zamboanga Peninsula", "#1565c0"),
    ("zscmst", "ZSCMST", "Zamboanga State College of Marine Sciences and Technology", "Zamboanga Peninsula", "#0277bd"),
    ("jhcsc", "JHCSC", "J.H. Cerilles State College", "Zamboanga Peninsula", "#2e7d32"),
    ("msuiit", "MSU-IIT", "Mindanao State University–Iligan Institute of Technology", "Northern Mindanao", "#8e1b1b"),
    ("ustp", "USTP", "University of Science and Technology of Southern Philippines", "Northern Mindanao", "#3949ab"),
    ("cmu", "CMU", "Central Mindanao University", "Northern Mindanao", "#2e7d32"),
    ("buksu", "BukSU", "Bukidnon State University", "Northern Mindanao", "#1565c0"),
    ("nmsc", "NMSC", "Northwestern Mindanao State College of Science and Technology", "Northern Mindanao", "#00897b"),
    ("cpsc", "CPSC", "Camiguin Polytechnic State College", "Northern Mindanao", "#f57f17"),
    ("usep", "USeP", "University of Southeastern Philippines", "Davao", "#b71c1c"),
    ("dnsc", "DNSC", "Davao del Norte State College", "Davao", "#2e7d32"),
    ("dorsu", "DOrSU", "Davao Oriental State University", "Davao", "#1565c0"),
    ("dssc", "DSSC", "Davao del Sur State College", "Davao", "#6a1b9a"),
    ("usm", "USM", "University of Southern Mindanao", "SOCCSKSARGEN", "#2e7d32"),
    ("msugensan", "MSU GenSan", "Mindanao State University–General Santos", "SOCCSKSARGEN", "#8e1b1b"),
    ("sksu", "SKSU", "Sultan Kudarat State University", "SOCCSKSARGEN", "#c62828"),
    ("cfcst", "CFCST", "Cotabato Foundation College of Science and Technology", "SOCCSKSARGEN", "#558b2f"),
    ("carsu", "CarSU", "Caraga State University", "Caraga", "#1565c0"),
    ("nemsu", "NEMSU", "North Eastern Mindanao State University", "Caraga", "#2e7d32"),
    ("snsu", "SNSU", "Surigao del Norte State University", "Caraga", "#f9a825"),
    ("asscat", "ASSCAT", "Agusan del Sur State College of Agriculture and Technology", "Caraga", "#388e3c"),
    ("msu", "MSU", "Mindanao State University", "BARMM", "#8e1b1b"),
    ("msutcto", "MSU-TCTO", "Mindanao State University–Tawi-Tawi College of Technology and Oceanography", "BARMM", "#00838f"),
    ("cotsu", "CotSU", "Cotabato State University", "BARMM", "#2e7d32"),
    ("sulu", "SSC Sulu", "Sulu State College", "BARMM", "#1565c0"),
    ("basilan", "BasSC", "Basilan State College", "BARMM", "#c62828"),
    ("msumaguindanao", "MSU Maguindanao", "Mindanao State University–Maguindanao", "BARMM", "#6a1b9a"),
];

/// RGB from "#rrggbb".
fn rgb(hex: &str) -> [f32; 3] {
    let v = u32::from_str_radix(&hex[1..], 16).unwrap_or(0);
    [(v >> 16) as f32 / 255.0, ((v >> 8) & 255) as f32 / 255.0, (v & 255) as f32 / 255.0]
}

fn hsl([r, g, b]: [f32; 3]) -> [f32; 3] {
    let (max, min) = (r.max(g).max(b), r.min(g).min(b));
    let l = (max + min) / 2.0;
    let d = max - min;
    if d == 0.0 {
        return [0.0, 0.0, l];
    }
    let s = d / (1.0 - (2.0 * l - 1.0).abs());
    let h = if max == r { ((g - b) / d).rem_euclid(6.0) } else if max == g { (b - r) / d + 2.0 } else { (r - g) / d + 4.0 };
    [h * 60.0, s, l]
}

fn hex([h, s, l]: [f32; 3]) -> String {
    let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
    let x = c * (1.0 - ((h / 60.0).rem_euclid(2.0) - 1.0).abs());
    let (r, g, b) = match (h / 60.0) as u32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    let m = l - c / 2.0;
    let to = |v: f32| ((v + m).clamp(0.0, 1.0) * 255.0).round() as u32;
    format!("#{:02x}{:02x}{:02x}", to(r), to(g), to(b))
}

/// A five-tone ramp, darkest first, and an accent light enough to read on the
/// landing's dark sky, all in the hue of `base`.
pub fn theme_from(base: &str) -> ([String; 5], String) {
    let [h, s, l] = hsl(rgb(base));
    let s = s.clamp(0.35, 0.8);
    let ramp = [0.1, 0.2, 0.36, 0.56, 0.84].map(|l| hex([h, s, l]));
    (ramp, hex([h, s.max(0.6), l.max(0.64)]))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn luminance(c: &str) -> f32 {
        let lin = |v: f32| if v <= 0.03928 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) };
        let [r, g, b] = rgb(c).map(lin);
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    #[test]
    fn ramps_run_dark_to_light_and_accents_read_on_the_sky() {
        let sky = luminance("#0b0710");
        for (id, .., base) in ROWS {
            let (ramp, accent) = theme_from(base);
            for w in ramp.windows(2) {
                assert!(luminance(&w[0]) < luminance(&w[1]), "{id} {ramp:?}");
            }
            assert!((luminance(&accent) + 0.05) / (sky + 0.05) >= 4.5, "{id} {accent}");
        }
    }

    #[test]
    fn hex_round_trips() {
        for c in ["#c62828", "#1565c0", "#2e7d32", "#f9a825", "#808080"] {
            let back = hex(hsl(rgb(c)));
            let d: i32 = rgb(c).iter().zip(rgb(&back)).map(|(a, b)| ((a - b) * 255.0).abs().round() as i32).max().unwrap();
            assert!(d <= 1, "{c} {back}");
        }
    }
}
