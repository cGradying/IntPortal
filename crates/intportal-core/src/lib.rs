//! IntPortal's core: SIS access, parsing and the domain logic every screen
//! reads. No UI, no platform APIs; the Tauri shell calls into this.

pub mod calendar;
pub mod campus;
pub mod grades;
pub mod model;
pub mod notes;
pub mod schedule;
pub mod sis;
pub mod store;
pub mod study;
pub mod syllabus;
pub mod today;
