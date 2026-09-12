ALTER TABLE "Circle"
ADD COLUMN "defaultThemeKey" TEXT,
ADD COLUMN "defaultThemeTitle" TEXT,
ADD COLUMN "defaultThemeNote" TEXT;

ALTER TABLE "CircleWeek"
ADD COLUMN "themeKey" TEXT,
ADD COLUMN "themeTitle" TEXT,
ADD COLUMN "themeNote" TEXT;
