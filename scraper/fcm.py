import json
import os

import google.auth.transport.requests
import httpx
from google.oauth2 import service_account

FCM_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]
FCM_URL = "https://fcm.googleapis.com/v1/projects/shiftfeed-98680/messages:send"


class FCMSender:
    def __init__(self) -> None:
        sa_file = os.getenv(
            "FIREBASE_SERVICE_ACCOUNT_FILE", "firebase-service-account.json"
        )
        sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")

        if sa_json:
            sa_info = json.loads(sa_json)
            self.credentials = service_account.Credentials.from_service_account_info(
                sa_info, scopes=FCM_SCOPES
            )
        elif os.path.exists(sa_file):
            self.credentials = service_account.Credentials.from_service_account_file(
                sa_file, scopes=FCM_SCOPES
            )
        else:
            print("WARNING: No Firebase service account found. FCM disabled.")
            self.credentials = None

    def _get_access_token(self) -> str:
        request = google.auth.transport.requests.Request()
        self.credentials.refresh(request)
        return self.credentials.token

    def send_to_topic(
        self,
        topic: str,
        title: str,
        body: str,
        data: dict | None = None,
    ) -> bool:
        if not self.credentials:
            return False
        try:
            token = self._get_access_token()
            message = {
                "message": {
                    "topic": topic,
                    "notification": {
                        "title": title,
                        "body": body,
                    },
                    "data": {k: str(v) for k, v in (data or {}).items()},
                    "android": {
                        "priority": "high",
                        "notification": {
                            "channel_id": "shiftfeed_alerts",
                            "color": "#EE0000",
                        },
                    },
                }
            }
            response = httpx.post(
                FCM_URL,
                json=message,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                },
                timeout=10,
            )
            if response.status_code == 200:
                print(f"FCM sent to topic '{topic}': {title}")
                return True
            print(f"FCM error {response.status_code}: {response.text}")
            return False
        except Exception as e:
            print(f"FCM exception: {e}")
            return False

    def send_to_token(
        self,
        token: str,
        title: str,
        body: str,
        data: dict | None = None,
    ) -> bool:
        """
        Sends a targeted FCM push to a single device token.

        Returns True on success, False on failure (token expired/invalid).
        Invalid tokens (404/410) are silently treated as False so the caller
        can prune them from ``user_device_tokens``.
        """
        if not self.credentials:
            return False
        try:
            access_token = self._get_access_token()
            message = {
                "message": {
                    "token": token,
                    "notification": {
                        "title": title,
                        "body": body,
                    },
                    "data": {k: str(v) for k, v in (data or {}).items()},
                    "android": {
                        "priority": "high",
                        "notification": {
                            "channel_id": "shiftfeed_alerts",
                            "color": "#EE0000",
                        },
                    },
                }
            }
            response = httpx.post(
                FCM_URL,
                json=message,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json",
                },
                timeout=10,
            )
            if response.status_code == 200:
                print(f"FCM sent to token: {title}")
                return True
            if response.status_code in (404, 410):
                # UNREGISTERED / NOT_FOUND — caller should prune.
                return False
            print(f"FCM token-send error {response.status_code}: {response.text}")
            return False
        except Exception as e:
            print(f"FCM token-send exception: {e}")
            return False

    def prune_stale_token(self, supabase, token: str) -> None:
        """Removes a stale/invalid FCM token from user_device_tokens."""
        try:
            supabase.table("user_device_tokens").delete().eq(
                "fcm_token", token
            ).execute()
        except Exception as e:
            print(f"[FCM] Failed to prune stale token: {e}")

    def send_cve_alert(
        self, cve_id: str, title: str, severity: str, url: str
    ) -> None:
        severity_upper = severity.upper() if severity else "UNKNOWN"
        self.send_to_topic(
            topic="security",
            title=f"🔴 {severity_upper}: {cve_id}",
            body=title[:100],
            data={"url": url, "cve_id": cve_id, "type": "cve"},
        )

    def send_release_alert(self, title: str, url: str) -> None:
        self.send_to_topic(
            topic="releases",
            title="🚀 New Release",
            body=title[:100],
            data={"url": url, "type": "release"},
        )
