# Gson uses generic type information stored in a class file's Signature
# attribute at runtime (e.g. via TypeToken) to deserialize collections such as
# List<WidgetProject>. R8 strips this attribute by default, which silently
# degrades Gson to raw types and causes ClassCastExceptions when the
# resulting elements are accessed as their real type (see
# WidgetConfigureActivity, which reads a Gson-serialized List<WidgetProject>
# from SharedPreferences).
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-dontwarn sun.misc.**
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep classes that are deserialized by Gson via reflection so field names
# and the no-args/constructor shape survive obfuscation.
-keep class io.vikunja.app.widget.WidgetProject { *; }
