export type AuthContext = {
  firebaseUid: string;
  email: string | null;
  emails: string[];
  emailVerified: boolean;
  name: string | null;
  picture: string | null;
  phoneNumber: string | null;
  phoneNumbers: string[];
  providerIds: string[];
  signInProvider: string | null;
};

export type AppEnv = {
  Variables: {
    auth: AuthContext | null;
  };
};
