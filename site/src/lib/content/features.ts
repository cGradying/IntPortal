// PLACEHOLDER until #326 lands: the Code engineer writes the real directory.
// Keep the exports and shapes; the content here is a small true sample.
import type { Feature, Group } from "./types";

export const GROUPS: { id: Group; name: string; line: string }[] = [
  { id: "signin", name: "Signing in", line: "The portal, your school, and a login that stays on your phone." },
  { id: "today", name: "Today", line: "What's on now, what's next, and what's due." },
  { id: "schedule", name: "Schedule", line: "Your week as SIS has it, with your own marks on it." },
  { id: "grades", name: "Grades", line: "Every term, your GPA and where it's heading." },
  { id: "study", name: "Study", line: "Notes, decks, and a session that plays like a game." },
  { id: "lar", name: "LAR", line: "The robot from the other side, and his assistant." },
  { id: "you", name: "You", line: "Looks, reminders, backup and the rest of your settings." },
  { id: "outside", name: "Outside the app", line: "Reminders, the Lock Screen and the calendar." },
  { id: "everywhere", name: "Everywhere", line: "Phones, computers and the browser." },
];

export const FEATURES: Feature[] = [
  { slug: "up-next", name: "Up next", group: "today", line: "Your next class with a countdown.", body: ["The class in session counts down; between classes, the next one does."], steps: ["Open Today."], media: { src: "/media/today.webp", alt: "Today with the class in session" }, since: "0.1.0", spec: "042-lar-plans-the-day" },
  { slug: "deadlines", name: "Deadlines", group: "today", line: "SIS, eMabini and your own, in one list.", body: ["Tick Done, and Undo if your thumb slipped."], steps: ["Tap Done beside a deadline."], media: { src: "/media/done.mp4", poster: "/media/done-poster.webp", video: true, alt: "Ticking a deadline Done" }, since: "0.2.0", spec: "041-one-deadline-list" },
  { slug: "week", name: "Day and week", group: "schedule", line: "Your classes on a grid with a line at now.", body: ["Mark a class vacant or online, move it for a week."], steps: ["Open Schedule."], media: { src: "/media/schedule.webp", alt: "The day schedule" }, since: "0.1.0", spec: "044-pixel-week" },
  { slug: "gpa", name: "GPA and trend", group: "grades", line: "Every term and where it's heading.", body: ["Your GPA this term and overall."], steps: ["Open Grades."], media: { src: "/media/grades.webp", alt: "Grades with the GPA trend" }, since: "0.1.0" },
  { slug: "study-game", name: "The study game", group: "study", line: "Cards deal, flip and build a streak.", body: ["A streak multiplies your points."], steps: ["Open a deck and tap Review."], since: "0.4.0", spec: "055-study-game" },
  { slug: "lar-chat", name: "Ask LAR", group: "lar", line: "Questions about your classes and notes, on the phone.", body: ["Turn on his assistant in You."], steps: ["Tap the crystal."], media: { src: "/media/talk.webp", alt: "LAR talking" }, since: "0.1.3", spec: "048-lar-chat" },
  { slug: "themes", name: "Looks and themes", group: "you", line: "Rooms, colours and themes you can share.", body: ["Share a theme by code or QR."], steps: ["Open You, then Look."], since: "0.2.0", spec: "047-you-and-themes" },
  { slug: "reminders", name: "Reminders", group: "outside", line: "Before class and before things are due.", body: ["Pick how early."], steps: ["Turn them on in You."], since: "0.1.0" },
  { slug: "sign-in", name: "Sign in", group: "signin", line: "Student number, birthdate and password.", body: ["Your login goes to the phone's keychain."], steps: ["Pick your portal and sign in."], media: { src: "/media/dive.mp4", poster: "/media/dive-poster.webp", video: true, alt: "The dive into Today" }, since: "0.1.0", spec: "011-login" },
  { slug: "desktop", name: "On your computer", group: "everywhere", line: "Mac, Windows and Linux.", body: ["The same app in a phone-sized window."], steps: ["Download it for your computer."], since: "0.4.0", spec: "053-desktop" },
];
