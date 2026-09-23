#!/usr/bin/env python3
"""Configure the nonlocalized Shoes On App Store listing fields: rights, copyright,
release type, categories, age rating, and the App Review contact and notes."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402


BUNDLE_ID = "com.jackwallner.time"
APP_NAME = "Shoes On"
# Age-rating answers are copied from a live health app and then overridden
# below. This pointed at the retired Protein Tracker record, so the copy
# would start failing the moment that record went away.
AGE_TEMPLATE_BUNDLE_ID = os.environ.get(
    "ASC_AGE_TEMPLATE_BUNDLE_ID", "com.jackwallner.vitals"
)
REVIEW_NOTES = """Shoes On is a leave-on-time routine coach. There is no account of any kind, so no demo account is needed.

WHAT A FRESH INSTALL SHOWS
1. Onboarding asks how far the user's time guesses usually run over, when they leave, on which days, and the steps before leaving (with guessed minutes). It then shows the real plan: the guess against the realistic time, and when to start.
2. After the notification permission prompt, the last onboarding page offers Shoes On Pro with a 7-day free trial. "Get Started" skips it; everything below works without a purchase.
3. Home shows the next departure (when to start, when to leave), the plan as a timeline, and how recent departures went.
4. Tap Start now to run the routine: one step at a time with a countdown dial, whether the user is on track or behind, and a Done button. The same run appears as a Live Activity on the Lock Screen with a Done button. After the last step, "I'm out the door" records the departure and shows each step's guess against its real time.

HOW IT LEARNS
Each Done tap times the step. The plan blends those timings into each step's estimate, learns an overall pace for untimed steps, and learns the delay between the get-ready alert and actually starting. Settings > Forget my real times resets it.

SHOES ON PRO (com.jackwallner.time.yearly, com.jackwallner.time.monthly, one-week free trial on both)
Unlocks more than one routine and the Apple Watch app. The first routine, every alert, the Live Activity and all the learning are free. The paywall opens from the routine menu (New routine) and from Settings > Try Shoes On Pro.

APPLE WATCH
The Watch app mirrors the run from the iPhone (step, countdown, status, Done, Skip) and can start the next routine. Without Pro it explains that the Watch coach is part of Pro.

NOTIFICATIONS
Local only, Time Sensitive (the entitlement is used for get-ready, wrap-up and leave alerts, which are time-critical by nature). If a trial starts, a reminder is scheduled two days before it ends.

NOT A MEDICAL APP
Shoes On is a planning aid. It does not diagnose, treat or manage ADHD or any condition, and says so in the description and the Terms.

PRIVACY
Routines and timings stay on the device and the paired Apple Watch. RevenueCat receives an anonymous app user id, purchase state and coarse purchase-screen counters."""


def review_phone() -> str:
    """The App Review contact number, which never belongs in a public repo.

    Sourced from ASC_REVIEW_PHONE, or from the shell-sourced
    ``~/.time_credentials`` that the other scripts here already read.
    """
    value = os.environ.get("ASC_REVIEW_PHONE")
    if value:
        return value.strip()
    path = Path.home() / ".time_credentials"
    if path.exists():
        for line in path.read_text().splitlines():
            key, _, raw = line.partition("=")
            key = key.strip().removeprefix("export ").strip()
            if key == "ASC_REVIEW_PHONE":
                return raw.strip().strip('"').strip("'")
    raise SystemExit(
        "error: set ASC_REVIEW_PHONE, or add it to ~/.time_credentials.\n"
        "The App Review contact number is deliberately not stored in this repo."
    )


def main() -> None:
    """`--notes-only` updates the App Review contact and notes and leaves the
    rights, copyright and age rating alone."""
    if not REVIEW_NOTES.strip():
        raise SystemExit("error: write REVIEW_NOTES before configuring the listing")
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])
    if not info or not version:
        raise SystemExit("error: Shoes On needs an editable app info and version")
    if "--notes-only" not in sys.argv:
        configure_listing(client, app, info, version)
    configure_review(client, version)
    print(f"configured {APP_NAME} ({app['id']})")


def configure_listing(client: A.ASCClient, app: dict, info: dict, version: dict) -> None:

    client.patch(
        f"/apps/{app['id']}",
        {
            "data": {
                "type": "apps",
                "id": app["id"],
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                },
            }
        },
    )
    client.patch(
        f"/appStoreVersions/{version['id']}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": {
                    "copyright": "2026 Jack Wallner",
                    "releaseType": "MANUAL",
                },
            }
        },
    )
    client.patch(
        f"/appInfos/{info['id']}",
        {
            "data": {
                "type": "appInfos",
                "id": info["id"],
                "relationships": {
                    "primaryCategory": {"data": {"type": "appCategories", "id": "PRODUCTIVITY"}},
                    "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}},
                },
            }
        },
    )
    age = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    template_app = A.find_app(client, AGE_TEMPLATE_BUNDLE_ID)
    template_info = A.find_editable_app_info(client, template_app["id"])
    template_age = client.get(
        f"/appInfos/{template_info['id']}/ageRatingDeclaration"
    )["data"]["attributes"]
    attrs = {key: value for key, value in template_age.items() if value is not None}
    attrs.pop("ageRatingOverride", None)
    attrs.update(
        {
            "healthOrWellnessTopics": False,
            "medicalOrTreatmentInformation": "NONE",
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        }
    )
    client.patch(
        f"/ageRatingDeclarations/{age['id']}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": age["id"],
                "attributes": attrs,
            }
        },
    )



def configure_review(client: A.ASCClient, version: dict) -> None:
    review = client.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attributes = {
        "contactFirstName": "Jack",
        "contactLastName": "Wallner",
        "contactPhone": review_phone(),
        "contactEmail": "jackwallner@gmail.com",
        "demoAccountRequired": False,
        "notes": REVIEW_NOTES,
    }
    if review:
        client.patch(
            f"/appStoreReviewDetails/{review['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": review["id"],
                    "attributes": attributes,
                }
            },
        )
    else:
        client.post(
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version["id"]}
                        }
                    },
                }
            },
        )


if __name__ == "__main__":
    main()
