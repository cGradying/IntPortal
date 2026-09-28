//! Grades: typed subject rows, the units-weighted GPA, and the average still
//! needed to reach a target.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// One row of the SIS grades table, as scraped.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct GradeRow {
    pub subject_code: String,
    pub description: String,
    pub faculty: String,
    pub unit: String,
    pub section_code: String,
    pub final_grade: String,
    pub grade_status: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SubjectGrade {
    pub subject_code: String,
    pub description: String,
    pub faculty: String,
    pub units: f64,
    pub section_code: String,
    /// As printed: `1.00`, empty (not posted yet), or a mark like `INC` or `DRP`.
    pub final_grade: String,
    pub grade_status: String,
    #[serde(default)]
    pub occurrence: u16,
}

impl SubjectGrade {
    pub fn id(&self) -> String {
        let base = if self.section_code.is_empty() {
            self.subject_code.clone()
        } else {
            format!("{}-{}", self.subject_code, self.section_code)
        };
        if self.occurrence == 0 {
            base
        } else {
            format!("{base}-{}", self.occurrence)
        }
    }

    /// Only a posted numeric grade. PUP runs 1.00 (best) to 5.00 (fail);
    /// blank, INC and DRP are `None`, never zero.
    pub fn numeric(&self) -> Option<f64> {
        self.final_grade.trim().parse().ok()
    }

    pub fn is_posted(&self) -> bool {
        self.numeric().is_some()
    }
}

/// Everything one term's grades page yields.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GradeReport {
    pub subjects: Vec<SubjectGrade>,
    /// The page's `<dl>` summary (Admission Status, Scholastic Status, GPA), raw.
    pub summary: BTreeMap<String, String>,
    pub school_year: Option<String>,
    pub semester: Option<String>,
}

impl GradeReport {
    pub fn gpa(&self) -> Option<f64> {
        gpa(&self.subjects)
    }

    pub fn has_posted_grades(&self) -> bool {
        self.subjects.iter().any(SubjectGrade::is_posted)
    }

    /// Oldest first: start year times ten plus the semester's rank
    /// (1st, 2nd, then summer).
    pub fn term_order(&self) -> i32 {
        let year = self.school_year.as_deref().and_then(|y| y.split(|c: char| !c.is_ascii_digit()).next()?.parse().ok()).unwrap_or(0);
        let s = self.semester.as_deref().unwrap_or("").to_lowercase();
        let rank = if s.contains("1st") || s.contains("first") {
            1
        } else if s.contains("2nd") || s.contains("second") {
            2
        } else if s.contains("summer") || s.contains("mid") {
            3
        } else {
            0
        };
        year * 10 + rank
    }

    /// Posted units only, so unposted, INC and DRP don't inflate it.
    pub fn completed_units(&self) -> f64 {
        self.subjects.iter().filter(|s| s.is_posted()).map(|s| s.units).sum()
    }
}

/// Rows with no subject code are spacers or totals lines and are skipped.
pub fn parse(rows: &[GradeRow]) -> Vec<SubjectGrade> {
    let mut seen: HashMap<String, u16> = HashMap::new();
    rows.iter()
        .filter(|r| !r.subject_code.trim().is_empty())
        .map(|r| {
            let mut g = SubjectGrade {
                subject_code: r.subject_code.trim().into(),
                description: r.description.trim().into(),
                faculty: r.faculty.trim().into(),
                units: r.unit.trim().parse().unwrap_or(0.0),
                section_code: r.section_code.trim().into(),
                final_grade: r.final_grade.trim().into(),
                grade_status: r.grade_status.trim().into(),
                occurrence: 0,
            };
            let n = seen.entry(g.id()).or_default();
            g.occurrence = *n;
            *n += 1;
            g
        })
        .collect()
}

fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

fn posted(subjects: &[SubjectGrade]) -> impl Iterator<Item = (f64, f64)> + '_ {
    subjects.iter().filter_map(|s| Some((s.numeric()?, s.units)).filter(|(_, u)| *u > 0.0))
}

/// Units-weighted average of posted numeric grades. `None` when nothing is
/// posted, which reads as "no GPA" rather than a misleading 0.00.
pub fn gpa(subjects: &[SubjectGrade]) -> Option<f64> {
    let (weighted, units) = posted(subjects).fold((0.0, 0.0), |(w, u), (g, n)| (w + g * n, u + n));
    (units > 0.0).then(|| round2(weighted / units))
}

/// The average needed on every unposted subject to land the term at `target`.
/// `None` when nothing with units is left to post.
pub fn needed_average(subjects: &[SubjectGrade], target: f64) -> Option<f64> {
    let remaining: f64 = subjects.iter().filter(|s| !s.is_posted() && s.units > 0.0).map(|s| s.units).sum();
    if remaining <= 0.0 {
        return None;
    }
    let (weighted, units) = posted(subjects).fold((0.0, 0.0), |(w, u), (g, n)| (w + g * n, u + n));
    Some(round2((target * (units + remaining) - weighted) / remaining))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(code: &str, units: &str, grade: &str) -> GradeRow {
        GradeRow {
            subject_code: code.into(),
            description: "Test Subject".into(),
            faculty: "SANTOS, JUAN".into(),
            unit: units.into(),
            section_code: "1".into(),
            final_grade: grade.into(),
            grade_status: String::new(),
        }
    }

    #[test]
    fn parses_every_field() {
        let mut r = row("COMP 20073", "3", "1.75");
        r.grade_status = "Passed".into();
        let g = &parse(&[r])[0];
        assert_eq!((g.subject_code.as_str(), g.units, g.final_grade.as_str()), ("COMP 20073", 3.0, "1.75"));
        assert_eq!(g.grade_status, "Passed");
        assert!(g.is_posted());
    }

    #[test]
    fn unposted_grade_still_lists_the_subject() {
        let g = &parse(&[row("COMP 20073", "3", "")])[0];
        assert_eq!(g.subject_code, "COMP 20073");
        assert_eq!(g.numeric(), None);
    }

    #[test]
    fn rows_without_a_subject_code_are_skipped() {
        let g = parse(&[row("", "0", ""), row("COMP 20073", "3", "1.00")]);
        assert_eq!(g.len(), 1);
        assert_eq!(g[0].subject_code, "COMP 20073");
    }

    #[test]
    fn all_unposted_has_no_gpa() {
        assert_eq!(gpa(&parse(&[row("COMP 20073", "3", ""), row("GEED 005", "3", "")])), None);
    }

    #[test]
    fn gpa_weights_only_posted_subjects() {
        let g = parse(&[row("COMP 20073", "3", "1.00"), row("GEED 005", "1", "2.00"), row("PATHFIT 1", "2", "")]);
        assert_eq!(gpa(&g), Some(1.25));
    }

    #[test]
    fn non_numeric_marks_are_listed_but_not_averaged() {
        let g = parse(&[row("COMP 20073", "3", "1.50"), row("GEED 005", "3", "INC"), row("PATHFIT 1", "2", "DRP")]);
        assert_eq!(g.len(), 3);
        assert_eq!(gpa(&g), Some(1.50));
    }

    #[test]
    fn zero_unit_subjects_do_not_break_the_average() {
        assert_eq!(gpa(&parse(&[row("COMP 20073", "3", "2.00"), row("NSTP 001", "0", "1.00")])), Some(2.00));
    }

    #[test]
    fn ids_are_unique_across_sections_and_duplicate_rows() {
        let mut other = row("COMP 20073", "3", "2.00");
        other.section_code = "2".into();
        let dup = row("COMP 20073", "3", "1.00");
        let ids: Vec<String> = parse(&[dup.clone(), other, dup]).iter().map(SubjectGrade::id).collect();
        assert_eq!(ids, ["COMP 20073-1", "COMP 20073-2", "COMP 20073-1-1"]);
    }

    #[test]
    fn term_order_is_chronological() {
        let r = |y: &str, s: &str| GradeReport { subjects: vec![], summary: BTreeMap::new(), school_year: Some(y.into()), semester: Some(s.into()) }.term_order();
        assert_eq!([r("2025-2026", "First Semester"), r("2025-2026", "2nd Semester"), r("2025-2026", "Summer"), r("2026-2027", "1st Semester")], [20251, 20252, 20253, 20261]);
    }

    #[test]
    fn needed_average_solves_for_the_remaining_units() {
        let g = parse(&[row("COMP 20073", "3", "1.00"), row("MATH 20073", "3", "")]);
        assert_eq!(needed_average(&g, 1.50), Some(2.00));
        assert_eq!(needed_average(&parse(&[row("COMP 20073", "3", "1.00")]), 1.50), None);
    }
}
