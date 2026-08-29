export type CoachPersonaId = "plainstride_supportive_v1" | "plainstride_focused_v1" | "plainstride_calm_v1";
export type VoiceProfileId = "plainstride_warm_1" | "plainstride_clear_1";
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
  recentInsight: string;     // one-line guide observation
}

// The downloadable artifact synced to device
export interface GuideProfilePayload {
  version: number;
  guideName: string;
  coachPersonaId: CoachPersonaId;
  voiceProfileId: VoiceProfileId;
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
  builtAt: string;          // ISO datetime
}
