# Kotlin serialization uses generated serializers; retain annotations/signatures used by Retrofit.
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> { static <1>$Companion Companion; }
-if @kotlinx.serialization.Serializable class ** { static **$Companion Companion; }
-keepclassmembers class <1>$Companion { kotlinx.serialization.KSerializer serializer(...); }

# Retrofit reads service method and parameter annotations at runtime.
-keep,allowoptimization,allowshrinking interface * { @retrofit2.http.* <methods>; }
-keepclasseswithmembers,allowshrinking,allowoptimization,includedescriptorclasses class * { @retrofit2.http.* <methods>; }
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement
