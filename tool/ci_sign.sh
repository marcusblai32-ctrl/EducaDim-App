#!/usr/bin/env bash
# Siyen release la ak kle pèmanan (secrets GitHub). Si secrets yo absan, pa fè anyen (kle debug).
set -euo pipefail
if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "AVERTISSEMENT: pas de clé de signature, APK signé avec la clé debug."; exit 0
fi
echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/upload.jks
cat > android/key.properties <<KP
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyPassword=${ANDROID_KEY_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
storeFile=upload.jks
KP
G=android/app/build.gradle.kts
[ -f "$G" ] || G=android/app/build.gradle
python3 - "$G" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read(); kts=p.endswith('.kts')
if 'key.properties' in s: sys.exit(0)
if kts:
    head='import java.io.FileInputStream\nimport java.util.Properties\n\n'
    load='val keystoreProperties = Properties()\nval keystorePropertiesFile = rootProject.file("key.properties")\nif (keystorePropertiesFile.exists()) { keystoreProperties.load(FileInputStream(keystorePropertiesFile)) }\n\n'
    sc='''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
'''
    s=head+s
    s=re.sub(r'(\nandroid\s*\{)', '\n'+load.rstrip()+'\n\\1', s, count=1)
    s=re.sub(r'(\n\s*buildTypes\s*\{)', '\n'+sc+'\\1', s, count=1)
    s=re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)','signingConfig = signingConfigs.getByName("release")',s)
    if 'getByName("release")' not in s:
        s=re.sub(r'(release\s*\{)', r'\1\n            signingConfig = signingConfigs.getByName("release")', s, count=1)
else:
    load='def keystoreProperties = new Properties()\ndef keystorePropertiesFile = rootProject.file("key.properties")\nif (keystorePropertiesFile.exists()) { keystoreProperties.load(new FileInputStream(keystorePropertiesFile)) }\n\n'
    sc='''    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
'''
    s=re.sub(r'(\nandroid\s*\{)', '\n'+load.rstrip()+'\n\\1', s, count=1)
    s=re.sub(r'(\n\s*buildTypes\s*\{)', '\n'+sc+'\\1', s, count=1)
    s=re.sub(r'signingConfig\s+signingConfigs\.debug','signingConfig signingConfigs.release',s)
open(p,'w').write(s)
PY
grep -q 'key.properties' "$G" || { echo "ERREUR: signature non appliquée"; exit 1; }
grep -q 'signingConfigs' "$G" || { echo "ERREUR: signingConfigs absent"; exit 1; }
echo "Signature release configurée."
