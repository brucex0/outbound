export type AuthContext = {
  subject: string;
  authenticationKind: "plainstride" | "provider";
  provider: "plainstride" | "firebase" | "apple" | "google";
  providerSubject: string;
  internalUserId: string | null;
  sessionId: string | null;
  email: string | null;
  emails: string[];
  emailVerified: boolean;
  name: string | null;
  picture: string | null;
  phoneNumber: string | null;
  phoneNumbers: string[];
};

export type AppEnv = {
  Variables: {
    auth: AuthContext | null;
    locale: "en" | "es" | "zh-Hans";
  };
};
