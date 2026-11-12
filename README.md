# HomeBar

![macOS](https://img.shields.io/badge/macOS-000000?style=flat&logo=apple&logoColor=F0F0F0)
![Swift](https://img.shields.io/badge/Swift-F54A2A?style=flat&logo=swift&logoColor=white)

A native macOS menu bar app for controlling Home Assistant.

## Instructions

### Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)

### Build and run

```sh
# build
./build.sh

# run
open .build/HomeBar.app
```

### Tests

```sh
./test.sh
```

## Connect to Home Assistant

1. Open Home Assistant and navigate to your profile → **Security**.
2. Under **Long-lived access tokens**, create a token and copy it (it will only be shown once).
3. Open HomeBar and enter your Home Assistant server URL.
4. Paste the token into Access Token and click Connect.

## Resources

- [Home Assistant WebSocket API](https://developers.home-assistant.io/docs/api/websocket/)
- [Home Assistant authentication API](https://developers.home-assistant.io/docs/auth_api/#long-lived-access-token)
