FROM oven/bun:1.1-alpine AS base
WORKDIR /app

COPY package.json bun.lockb ./
RUN bun install --frozen-lockfile

COPY . .
RUN bunx prisma generate

ENV PORT=3000
EXPOSE 3000

CMD ["bun", "run", "src/index.ts"]
