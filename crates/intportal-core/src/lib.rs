// Without the store and the network (the browser demo), their imports and helpers go unused.
#![cfg_attr(not(all(feature = "store", feature = "net")), allow(unused_imports, dead_code))]
//! IntPortal's core: SIS access, parsing and the domain logic every screen
//! reads. No UI, no platform APIs; the Tauri shell calls into this.

pub mod backup;
pub mod calendar;
pub mod campus;
pub mod coach;
pub mod deadline;
pub mod demo;
pub mod grades;
pub mod mabini;
pub mod model;
pub mod notes;
pub mod own_class;
pub mod nudge;
pub mod portal;
pub mod scan;
pub mod schedule;
pub mod schools;
pub mod sis;
pub mod store;
pub mod study;
pub mod syllabus;
pub mod timetable;
pub mod today;
pub mod when;
