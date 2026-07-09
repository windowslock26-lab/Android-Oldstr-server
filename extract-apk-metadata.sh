#!/bin/bash
# Extract APK metadata and update apps-manifest.json
# This script runs automatically on each release

set -e

RELEASE_TAG=${GITHUB_REF#refs/tags/}
RELEASE_URL="https://api.github.com/repos/$GITHUB_REPOSITORY/releases/tags/$RELEASE_TAG"

echo "Fetching release information for: $RELEASE_TAG"

# Get release assets
RELEASE_DATA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$RELEASE_URL")
echo "$RELEASE_DATA" > /tmp/release.json

# Create manifest file
cat > apps-manifest.json << 'EOF'
{
  "apps": [
EOF

FIRST=true

# Process each APK file
while read -r ASSET_NAME DOWNLOAD_URL; do
    if [[ "$ASSET_NAME" == *.apk ]]; then
        echo "Processing: $ASSET_NAME"
        
        # Download APK temporarily
        curl -s -L -o /tmp/temp.apk "$DOWNLOAD_URL"
        
        # Extract APK metadata using aapt (Android Asset Packaging Tool)
        # If aapt is not available, use defaults
        if command -v aapt &> /dev/null; then
            APP_NAME=$(aapt dump badging /tmp/temp.apk | grep "application-label:" | sed "s/application-label://g" | tr -d "'" | head -1)
            PACKAGE=$(aapt dump badging /tmp/temp.apk | grep "package:" | awk '{print $2}' | cut -d"'" -f2)
            VERSION=$(aapt dump badging /tmp/temp.apk | grep "versionName=" | sed "s/.*versionName='//g" | sed "s/'.*//g")
        else
            # Fallback to filename
            APP_NAME="${ASSET_NAME%.apk}"
            PACKAGE="com.unknown"
            VERSION="1.0"
        fi
        
        # Get file size in MB
        FILE_SIZE=$(ls -lh /tmp/temp.apk | awk '{print $5}' | sed 's/M//')
        
        # Try to extract icon (if available)
        ICON_URL=""
        # Icon extraction would require unzipping APK and converting binary resources
        # For simplicity, we'll leave this empty and use emoji fallback
        
        # Add to manifest
        if [ "$FIRST" = false ]; then
            echo "," >> apps-manifest.json
        fi
        FIRST=false
        
        cat >> apps-manifest.json << EOF
    {
      "name": "$APP_NAME",
      "package": "$PACKAGE",
      "version": "$VERSION",
      "size": "$FILE_SIZE",
      "filename": "$ASSET_NAME",
      "downloadUrl": "$DOWNLOAD_URL",
      "icon": "$ICON_URL"
    }
EOF
        
        rm -f /tmp/temp.apk
    fi
done < <(jq -r '.assets[] | .name + " " + .browser_download_url' /tmp/release.json)

# Close JSON
cat >> apps-manifest.json << 'EOF'
  ]
}
EOF

echo "Manifest updated successfully!"
cat apps-manifest.json

# Commit and push
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git config --global user.name "github-actions[bot]"
git add apps-manifest.json
git commit -m "Update apps manifest for release $RELEASE_TAG" || echo "No changes to commit"
git push origin main || echo "Failed to push (might be main branch protection)"
