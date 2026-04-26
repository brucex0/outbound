export type CoachPersonality = "encouraging" | "data-driven" | "direct" | "zen";
export type FitnessLevel = "beginner" | "intermediate" | "advanced" | "elite";

export interface GoalItem {
  type: "race" | "distance" | "pace" | "streak" | "weight";
  description: string;
  targetDate?: string;       // ISO date
  targetValue?: number;      // seconds, meters, etc.
  achieved: boolean;
}

export interface PersonalRecords {
  "1k"?: number;
  "5k"?: number;
  "10k"?: number;
  "half-marathon"?: number;
  "marathon"?: number;
  [key: string]: number | undefined;
}

export interface MemorySnapshot {
  recentActivities: {
    date: string;
    type: string;
    distanceKm: number;
    avgPaceSecs: number;
    notes?: string;
  }[];
  weeklyVolumeKm: number;
  longestRunKm: number;
  consistencyScore: number;  // 0-1
  recentInsight: string;     // one-line coach observation
}

// The downloadable artifact synced to device
export interface CoachProfilePayload {
  version: number;
  coachName: string;
  personality: CoachPersonality;
  voiceId: string;
  athlete: {
    fitnessLevel: FitnessLevel;
    weeklyVolumeKm: number;
    preferredPaceSecs?: number;
    strengths: string[];
    weaknesses: string[];
    records: PersonalRecords;
  };
  goals: GoalItem[];
  memorySnapshot: MemorySnapshot;
  systemPrompt: string;     // pre-built prompt for on-device model
  builtAt: string;          // ISO datetime
}
