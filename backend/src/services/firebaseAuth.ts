import { applicationDefault, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

function getFirebaseApp() {
  if (getApps().length > 0) {
    return getApps()[0]!;
  }

  return initializeApp({
    credential: applicationDefault(),
    projectId:
      process.env.FIREBASE_PROJECT_ID ??
      process.env.GOOGLE_CLOUD_PROJECT ??
      process.env.GCLOUD_PROJECT,
  });
}

export async function verifyBearerToken(token: string) {
  return getAuth(getFirebaseApp()).verifyIdToken(token);
}
