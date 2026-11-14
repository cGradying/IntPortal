//! The platform's keychain: Keychain Services on Apple, values sealed by
//! an Android Keystore key on Android (`Secrets.kt`). `Ok(None)` only
//! when nothing is saved under the name.

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn entry(service: &str, name: &str) -> Result<keyring::Entry, String> {
    keyring::Entry::new(service, name).map_err(|e| e.to_string())
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub fn get(service: &str, name: &str) -> Result<Option<String>, String> {
    match entry(service, name)?.get_password() {
        Ok(v) => Ok(Some(v)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub fn set(service: &str, name: &str, value: &str) -> Result<(), String> {
    entry(service, name)?.set_password(value).map_err(|e| e.to_string())
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub fn delete(service: &str, name: &str) {
    if let Ok(e) = entry(service, name) {
        let _ = e.delete_credential();
    }
}

#[cfg(target_os = "android")]
mod jvm {
    use jni::objects::{JClass, JObject, JString, JValue, JValueOwned};
    use jni::{JNIEnv, JavaVM};

    /// Calls a static method of `ph.intportal.app.Secrets` with the app
    /// context first. Works from any thread: the class comes through the
    /// app's class loader, which a native thread doesn't have.
    pub fn call<T>(
        method: &str,
        sig: &str,
        args: &[&str],
        read: impl FnOnce(&mut JNIEnv, JValueOwned) -> jni::errors::Result<T>,
    ) -> Result<T, String> {
        let ctx = ndk_context::android_context();
        let vm = unsafe { JavaVM::from_raw(ctx.vm().cast()) }.map_err(|e| e.to_string())?;
        let mut env = vm.attach_current_thread().map_err(|e| e.to_string())?;
        let context = unsafe { JObject::from_raw(ctx.context().cast()) };
        let out = env.with_local_frame(16, |env| {
            let loader = env.call_method(&context, "getClassLoader", "()Ljava/lang/ClassLoader;", &[])?.l()?;
            let class_name = env.new_string("ph.intportal.app.Secrets")?;
            let class = JClass::from(
                env.call_method(&loader, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;", &[JValue::Object(&class_name)])?.l()?,
            );
            let mut strings = Vec::with_capacity(args.len());
            for a in args {
                strings.push(JObject::from(env.new_string(a)?));
            }
            let mut jargs = vec![JValue::Object(&context)];
            jargs.extend(strings.iter().map(JValue::Object));
            let r = env.call_static_method(&class, method, sig, &jargs)?;
            read(env, r)
        });
        out.map_err(|e| {
            // A thrown exception stays pending until cleared; say what it was.
            if env.exception_check().unwrap_or(false) {
                let thrown = env.exception_occurred().ok();
                let _ = env.exception_clear();
                if let Some(t) = thrown {
                    if let Ok(m) = env.call_method(&t, "toString", "()Ljava/lang/String;", &[]).and_then(|v| v.l()) {
                        if let Ok(s) = env.get_string(&JString::from(m)) {
                            return String::from(s);
                        }
                    }
                }
            }
            e.to_string()
        })
    }
}

#[cfg(target_os = "android")]
fn key(service: &str, name: &str) -> String {
    format!("{service}/{name}")
}

#[cfg(target_os = "android")]
pub fn get(service: &str, name: &str) -> Result<Option<String>, String> {
    jvm::call("get", "(Landroid/content/Context;Ljava/lang/String;)Ljava/lang/String;", &[&key(service, name)], |env, v| {
        let o = v.l()?;
        if o.is_null() {
            return Ok(None);
        }
        Ok(Some(env.get_string(&jni::objects::JString::from(o))?.into()))
    })
}

#[cfg(target_os = "android")]
pub fn set(service: &str, name: &str, value: &str) -> Result<(), String> {
    jvm::call("set", "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V", &[&key(service, name), value], |_, _| Ok(()))
}

#[cfg(target_os = "android")]
pub fn delete(service: &str, name: &str) {
    let _ = jvm::call("delete", "(Landroid/content/Context;Ljava/lang/String;)V", &[&key(service, name)], |_, _| Ok(()));
}

// Desktop dev builds keep nothing.
#[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
pub fn get(_: &str, _: &str) -> Result<Option<String>, String> {
    Ok(None)
}
#[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
pub fn set(_: &str, _: &str, _: &str) -> Result<(), String> {
    Err("Saving your login isn't supported on this device yet.".into())
}
#[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
pub fn delete(_: &str, _: &str) {}
