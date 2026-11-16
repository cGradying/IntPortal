/** A phone: iOS or Android. On a desktop build or in the browser demo, the settings that need a phone (Face ID, haptics, the class card outside the app, the phone calendar) are hidden (spec 053 C5). */
export const isPhone = (ua: string = typeof navigator === "undefined" ? "" : navigator.userAgent) => /Android|iPhone|iPad|iPod/i.test(ua);

export const PHONE = isPhone();
