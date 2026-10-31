import Foundation

/// Fixed speech-recognition vocabulary; free-form intent uses LocalIntelligence.
enum AssistantRecognitionVocabulary {
    static var recognitionHints: [String] { switch AppLanguage.current {
    case .english: [
        "start a run",
        "start a bike",
        "start a 5K run",
        "start a 10K run",
        "start a 3K run",
        "start a 20 minute run",
        "start a 30 minute run",
        "start a 45 minute run",
        "bike for 30 minutes",
        "bike for 45 minutes",
        "ride for 30 minutes",
        "go for a run",
        "go for a bike ride",
        "5K",
        "10K",
        "kilometers",
        "minutes"
    ]
    case .spanish: ["inicia una carrera", "prepara una carrera de 5 kilómetros", "correr 30 minutos", "inicia un paseo en bicicleta", "kilómetros", "millas", "minutos"]
    case .simplifiedChinese: ["开始跑步", "准备五公里跑步", "跑三十分钟", "开始骑行", "公里", "英里", "分钟"]
    } }

}
