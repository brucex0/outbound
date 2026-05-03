export type AuthContext = {
  firebaseUid: string;
  email: string | null;
};

export type AppEnv = {
  Variables: {
    auth: AuthContext | null;
  };
};
