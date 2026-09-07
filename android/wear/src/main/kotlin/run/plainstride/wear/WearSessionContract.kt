package run.plainstride.wear

enum class WearSessionCommand {
    Start,
    Pause,
    Resume,
    Finish,
}

interface WearSessionGateway {
    suspend fun send(command: WearSessionCommand)
}
