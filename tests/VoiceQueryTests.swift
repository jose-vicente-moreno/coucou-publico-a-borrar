// tests/VoiceQueryTests.swift — questions, mail and app requests, spoken answers.
import Foundation

@main
struct VoiceQueryTests {
    nonisolated(unsafe) static var pass = 0
    nonisolated(unsafe) static var fail = 0

    static func check<T: Equatable>(_ label: String, _ got: T, _ want: T) {
        if got == want { print("✓  \(label)"); pass += 1 }
        else { print("✗  \(label) — got \(got), want \(want)"); fail += 1 }
    }
    static func contains(_ label: String, _ text: String, _ part: String) {
        if text.contains(part) { print("✓  \(label)"); pass += 1 }
        else { print("✗  \(label) — \"\(text)\" has no \"\(part)\""); fail += 1 }
    }

    static func main() {
        let pills = PillFixture.available
        // ── Topics: Louis's own questions ─────────────────────────────────────
        let topics: [(String, VoiceTopic?)] = [
            ("Quel temps il fait aujourd'hui ?", .weatherToday),
            ("il va pleuvoir demain ?", .weatherTomorrow),
            ("météo", .weatherToday),
            ("Combien d'argent j'ai fait aujourd'hui sur Stripe ?", .stripe),
            ("combien j'ai vendu aujourd'hui", .stripe),
            ("Mon push Vercel, est-ce qu'il a été push ?", .vercel),
            ("est-ce que mon déploiement est passé", .vercel),
            ("Combien d'étoiles j'ai sur GitHub ?", .github),
            ("combien d'étoiles j'ai", .github),
            ("Qu'est-ce qui se passe sur mon Claude Code ?", .agents),
            ("il en est où Codex ?", .agents),
            ("il me reste combien sur mon plan Claude ?", .claudePlan),
            ("c'est quoi mon usage Codex", .codexPlan),
            ("j'ai des rendez-vous aujourd'hui ?", .calcom),
            ("c'est quoi cette chanson", .music),
            ("quelles pilules sont actives", .pills),
            ("how many stars do I have on GitHub?", .github),
            ("what's the weather like?", .weatherToday),
            // Commands stay commands
            ("est-ce que tu peux ajouter GitHub", nil),
            ("ajoute Stripe", nil),
            ("mets du Drake", nil),
            ("On s'en fout c'est", nil),
        ]
        for (phrase, want) in topics { check("topic «\(phrase)»", VoiceQuery.topic(of: phrase), want) }

        // ── Through the parser ────────────────────────────────────────────────
        check("parse stripe question", IntentParser.parse("Combien d'argent j'ai fait aujourd'hui sur Stripe ?", pills: pills), .query(.stripe))
        check("parse add stays add", IntentParser.parse("ajoute la pilule Stripe", pills: pills), .pillAdd(id: "integration_stripe"))

        // ── Mail ──────────────────────────────────────────────────────────────
        check("mail to Tana", VoiceQuery.mail(of: "Envoie un mail à Tana"),
              VoiceQuery.MailRequest(recipient: "Tana", file: nil, folder: nil))
        check("mail file from downloads", VoiceQuery.mail(of: "envoie le fichier facture octobre des téléchargements à Tana"),
              VoiceQuery.MailRequest(recipient: "Tana", file: "facture octobre", folder: .downloads))
        check("mail file from desktop", VoiceQuery.mail(of: "envoie le fichier devis du bureau à Paul Martin"),
              VoiceQuery.MailRequest(recipient: "Paul Martin", file: "devis", folder: .desktop))
        check("send an email to", VoiceQuery.mail(of: "send an email to Tana"),
              VoiceQuery.MailRequest(recipient: "Tana", file: nil, folder: nil))
        check("not a mail", VoiceQuery.mail(of: "envoie la musique"), nil)
        check("guided mail (no recipient)", VoiceQuery.mail(of: "envoie un mail"),
              VoiceQuery.MailRequest(recipient: "", file: nil, folder: nil))
        check("guided mail EN", VoiceQuery.mail(of: "send an email"),
              VoiceQuery.MailRequest(recipient: "", file: nil, folder: nil))
        check("recipient answer", VoiceQuery.recipientAnswer("c'est Tana"), "Tana")
        check("recipient spoken email", VoiceQuery.recipientAnswer("tana arobase gmail point com"), "tana@gmail.com")
        check("subject answer", VoiceQuery.subjectAnswer("l'objet c'est Voilà votre image"), "Voilà votre image")
        check("no subject", VoiceQuery.subjectAnswer("pas d'objet"), "")
        check("body verbatim only on request", VoiceQuery.bodyAnswer("mot pour mot : Image en 1980 par 1080").body, "Image en 1980 par 1080")
        check("body plain answer is drafted", VoiceQuery.bodyAnswer("Image en 1980 par 1080").instruction, "Image en 1980 par 1080")
        check("body faut dire que", VoiceQuery.bodyAnswer("Faut dire que l'image est prête").instruction, "l'image est prête")
        check("body faut dire → no literal", VoiceQuery.bodyAnswer("Faut dire que l'image est prête").body, nil)
        check("body tell her", VoiceQuery.bodyAnswer("tell her that the file is ready").instruction, "the file is ready")
        check("simple mail fr", VoiceQuery.simpleMail(from: "faut dire que l'image est prête"), "Bonjour,\n\nL'image est prête.\n\nBonne journée !")
        check("simple mail en", VoiceQuery.simpleMail(from: "the file is ready"), "Hi,\n\nThe file is ready.\n\nBest,")
        check("looks French", VoiceQuery.textLanguage("l'image est prête"), .fr)
        check("looks English", VoiceQuery.textLanguage("the image is ready"), .en)
        check("mail pour lui dire → drafted", VoiceQuery.mail(of: "envoie un mail à Tana pour lui dire que l'image est prête")?.instruction, "l'image est prête")
        check("mail description → literal", VoiceQuery.mail(of: "envoie un mail à Tana avec le texte rendez-vous demain")?.body, "rendez-vous demain")
        check("body draft", VoiceQuery.bodyAnswer("écris-lui que je serai en retard").instruction, "je serai en retard")
        check("attachment name", VoiceQuery.attachmentAnswer("oui, Goku point png"), "Goku.png")
        // Louis's example, as dictated
        check("Goku mail", VoiceQuery.mail(of: "Il y a une image qui s'appelle Goku.png. J'aimerais que tu la prennes et que tu l'envoies par mail à tana@gmail.com. En objet, tu écris : Voilà votre image. En description, tu écris : Image en 1980 × 1080."),
              VoiceQuery.MailRequest(recipient: "tana@gmail.com", file: "Goku.png", folder: nil,
                                     subject: "Voilà votre image", body: "Image en 1980 × 1080"))
        check("Goku mail EN", VoiceQuery.mail(of: "email the image called Goku.png to tana@gmail.com, subject Here is your image, body Image in 1980 by 1080"),
              VoiceQuery.MailRequest(recipient: "tana@gmail.com", file: "Goku.png", folder: nil,
                                     subject: "Here is your image", body: "Image in 1980 by 1080"))
        check("spoken address", VoiceQuery.mail(of: "envoie un mail à tana arobase gmail point com"),
              VoiceQuery.MailRequest(recipient: "tana@gmail.com", file: nil, folder: nil))
        check("spoken address EN", VoiceQuery.spokenEmail("tana at gmail dot com"), "tana@gmail.com")
        check("file point png", VoiceQuery.mail(of: "envoie l'image goku point png à Tana")?.file, "goku.png")
        check("draft instruction", VoiceQuery.mail(of: "write an email to Tana thanking her for yesterday"),
              VoiceQuery.MailRequest(recipient: "Tana", file: nil, folder: nil, instruction: "thanking her for yesterday"))
        check("écris un mail = command", VoiceQuery.topic(of: "tu peux écrire un mail à Tana"), nil)
        check("parse écris un mail", IntentParser.parse("tu peux écrire un mail à Tana", pills: pills),
              .mail(VoiceQuery.MailRequest(recipient: "Tana", file: nil, folder: nil)))
        check("resend stats still work", VoiceQuery.topic(of: "combien de mails j'ai envoyé ?"), .resend)
        check("VS Code question", VoiceQuery.topic(of: "qu'est-ce qui se passe sur VS Code ?"), .agents)
        check("parse mail", IntentParser.parse("Envoie un mail à Intel", pills: pills),
              .mail(VoiceQuery.MailRequest(recipient: "Intel", file: nil, folder: nil)))

        // ── Apps ──────────────────────────────────────────────────────────────
        check("ouvre Figma", VoiceQuery.appToOpen("ouvre Figma"), "Figma")
        check("ouvre l'app Notes", VoiceQuery.appToOpen("ouvre l'app Notes"), "Notes")
        check("open Safari", VoiceQuery.appToOpen("open Safari"), "Safari")
        check("parse open app", IntentParser.parse("ouvre Figma", pills: pills), .openApp(name: "Figma"))

        // Guided mail: names and repeats
        check("recipient il s'appelle", VoiceQuery.recipientAnswer("Il s'appelle Enzo"), "Enzo")
        check("recipient son nom c'est", VoiceQuery.recipientAnswer("son nom c'est Enzo Martin"), "Enzo Martin")
        check("recipient his name is", VoiceQuery.recipientAnswer("his name is Paul"), "Paul")
        check("contact candidates", VoiceQuery.contactCandidates("mon pote Enzo"), ["mon pote Enzo", "Enzo"])
        check("collapse repeat", VoiceQuery.collapseRepeat("image image"), "image")
        check("collapse repeat two words", VoiceQuery.collapseRepeat("Voilà l'image voilà l'image"), "Voilà l'image")
        check("no collapse", VoiceQuery.collapseRepeat("bonjour Enzo"), "bonjour Enzo")

        // Web search
        check("web fr lead", VoiceQuery.webQuery(of: "cherche sur internet qui a gagné l'Euro"), "qui a gagné l'Euro")
        check("web fr tail", VoiceQuery.webQuery(of: "Cherche les horaires du Louvre sur internet"), "les horaires du Louvre")
        check("web fr recherche", VoiceQuery.webQuery(of: "fais une recherche internet sur Tesla"), "Tesla")
        check("web fr peux-tu", VoiceQuery.webQuery(of: "Est-ce que tu peux chercher sur le web le prix de l'iPhone 17 ?"), "le prix de l'iPhone 17")
        check("web en", VoiceQuery.webQuery(of: "search the web for the latest Apple news"), "the latest Apple news")
        check("web en look up", VoiceQuery.webQuery(of: "can you look up who won the Champions League"), "who won the Champions League")
        check("web google", VoiceQuery.webQuery(of: "Google the weather in Tokyo"), "the weather in Tokyo")
        check("web nothing after", VoiceQuery.webQuery(of: "cherche sur internet"), "")
        check("web not: open Google Chrome", VoiceQuery.webQuery(of: "ouvre Google Chrome"), nil)
        check("web not: plain search", VoiceQuery.webQuery(of: "cherche Daft Punk"), nil)
        check("parse web", IntentParser.parse("cherche sur internet la météo à Tokyo", pills: pills),
              .webSearch(query: "la météo à Tokyo"))
        check("question fr qui", VoiceQuery.looksLikeQuestion("qui a gagné le match hier"), true)
        check("question fr c'est quoi", VoiceQuery.looksLikeQuestion("c'est quoi un trou noir"), true)
        check("question fr et", VoiceQuery.looksLikeQuestion("et à Paris ?"), true)
        check("question en", VoiceQuery.looksLikeQuestion("what's the capital of Australia"), true)
        check("question en how", VoiceQuery.looksLikeQuestion("how tall is the Eiffel Tower"), true)
        check("not a question: request", VoiceQuery.looksLikeQuestion("tu peux mettre de la musique ?"), false)
        check("not a question: can you", VoiceQuery.looksLikeQuestion("can you play something chill"), false)
        check("not a question: command", VoiceQuery.looksLikeQuestion("mets du Daft Punk"), false)
        check("spoken markdown", VoiceQuery.spokenText("**Spain** won [the Euro](https://uefa.com) [1].\n- Final: 2-1"),
              "Spain won the Euro. Final: 2-1")
        check("spoken url", VoiceQuery.spokenText("See https://example.com for more."), "See for more.")

        // ── Answers ───────────────────────────────────────────────────────────
        var s = VoiceSnapshot()
        s.stripe = .init(balance: "1 240,00 €", today: "85,00 €", todayCount: 2, last: [])
        contains("stripe today fr", VoiceAnswer.text(.stripe, s, lang: .fr), "Aujourd'hui : 85,00 €, 2 paiements")
        s.stripe = .init(balance: "1 240,00 €", today: "0,00 €", todayCount: 0, last: [])
        contains("stripe no sale", VoiceAnswer.text(.stripe, s, lang: .fr), "Aucune vente aujourd'hui")
        s.github = .init(stars: 128, repos: 12,
                         myPRs: [.init(title: "a", repo: "r", ci: "failure", review: "pending"),
                                 .init(title: "b", repo: "r", ci: "success", review: "approved")],
                         toReview: 1, failingRepos: [])
        let gh = VoiceAnswer.text(.github, s, lang: .fr)
        contains("github stars", gh, "128 étoiles sur 12 repos")
        contains("github red CI", gh, "dont 1 avec la CI en échec")
        s.deploys = [.init(project: "korus", state: "ERROR", ago: "5 minutes", commit: nil),
                     .init(project: "korus", state: "READY", ago: "2 heures", commit: nil)]
        contains("vercel failed", VoiceAnswer.text(.vercel, s, lang: .fr), "korus a échoué, il y a 5 minutes")
        s.sessions = [.init(name: "Claude Code", state: "working", detail: "Edit IntentParser.swift")]
        contains("agents", VoiceAnswer.text(.agents, s, lang: .fr), "Claude Code travaille : Edit IntentParser.swift")
        s.approvalPending = "Bash"
        contains("approval first", VoiceAnswer.text(.agents, s, lang: .fr), "autorisation attend ton clic : Bash")
        var off = VoiceSnapshot(); off.configured = false
        contains("not configured", VoiceAnswer.text(.stripe, off, lang: .fr), "Stripe n'est pas connecté")
        var w = VoiceSnapshot()
        w.weatherOff = true
        contains("weather off", VoiceAnswer.text(.weatherToday, w, lang: .fr), "Active la météo")
        w.weatherOff = false
        w.weather = .init(city: "Bordeaux", nowTemp: 17, code: 61, min: 12, max: 19, rainChance: 70, wind: 20)
        let wt = VoiceAnswer.text(.weatherToday, w, lang: .fr)
        contains("weather now", wt, "À Bordeaux, 17 degrés, pluie")
        contains("weather rain", wt, "70 % de risque de pluie")
        contains("weather en", VoiceAnswer.text(.weatherTomorrow, w, lang: .en), "Tomorrow in Bordeaux: rain, 12 to 19 degrees")
        check("wmo 0", VoiceAnswer.weatherText(0, lang: .fr), "ciel dégagé")
        check("wmo 95", VoiceAnswer.weatherText(95, lang: .en), "thunderstorms")

        // ── Spanish ───────────────────────────────────────────────────────────
        let esTopics: [(String, VoiceTopic?)] = [
            ("¿Qué tiempo hace hoy?", .weatherToday),
            ("¿va a llover mañana?", .weatherTomorrow),
            ("¿llueve esta mañana?", .weatherToday),
            ("qué tiempo hará mañana por la mañana", .weatherTomorrow),
            ("¿Cuánto dinero he ganado hoy en Stripe?", .stripe),
            ("cuánto he vendido hoy", .stripe),
            ("¿Cuántas estrellas tengo en GitHub?", .github),
            ("¿ha pasado mi despliegue de Vercel?", .vercel),
            ("¿qué está haciendo Claude Code?", .agents),
            ("¿cuánto me queda en el plan de Claude?", .claudePlan),
            ("¿tengo citas hoy?", .calcom),
            ("¿qué canción es esta?", .music),
            ("¿qué píldoras están activas?", .pills),
            ("¿cuántos correos he enviado?", .resend),
            // Commands stay commands, and "tiempo" alone is not the weather
            ("¿puedes añadir GitHub?", nil),
            ("pon música", nil),
            ("quita Stripe", nil),
            ("cuánto tiempo falta", nil),
        ]
        for (phrase, want) in esTopics { check("es topic «\(phrase)»", VoiceQuery.topic(of: phrase), want) }
        check("es parse question", IntentParser.parse("¿Cuántas estrellas tengo en GitHub?", pills: pills), .query(.github))

        // Mail
        check("es mail to Tana", VoiceQuery.mail(of: "Envía un correo a Tana"),
              VoiceQuery.MailRequest(recipient: "Tana", file: nil, folder: nil))
        check("es guided mail", VoiceQuery.mail(of: "manda un correo"),
              VoiceQuery.MailRequest(recipient: "", file: nil, folder: nil))
        check("es write a mail", IntentParser.parse("escribe un correo a Paul", pills: pills),
              .mail(VoiceQuery.MailRequest(recipient: "Paul", file: nil, folder: nil)))
        check("es file from downloads", VoiceQuery.mail(of: "envía el archivo factura de descargas a Tana"),
              VoiceQuery.MailRequest(recipient: "Tana", file: "factura", folder: .downloads))
        check("es image que se llama", VoiceQuery.mail(of: "envía la imagen que se llama Goku.png por correo a tana@gmail.com con el asunto Aquí tienes tu imagen")?.file,
              "Goku.png")
        check("es image subject", VoiceQuery.mail(of: "envía la imagen que se llama Goku.png por correo a tana@gmail.com con el asunto Aquí tienes tu imagen")?.subject,
              "Aquí tienes tu imagen")
        check("es file punto png", VoiceQuery.mail(of: "envía la foto goku punto png a Tana")?.file, "goku.png")
        check("es instruction", VoiceQuery.mail(of: "envía un correo a Tana para decirle que la imagen está lista")?.instruction,
              "la imagen está lista")
        check("es literal body", VoiceQuery.mail(of: "envía un correo a Tana con el texto nos vemos mañana")?.body,
              "nos vemos mañana")
        check("es spoken address", VoiceQuery.mail(of: "envía un correo a tana arroba gmail punto com")?.recipient,
              "tana@gmail.com")
        check("es spoken guion", VoiceQuery.spokenEmail("ana guion bajo lopez arroba gmail punto com"), "ana_lopez@gmail.com")
        check("es recipient se llama", VoiceQuery.recipientAnswer("se llama Enzo"), "Enzo")
        check("es recipient es para", VoiceQuery.recipientAnswer("es para Lucía"), "Lucía")
        check("es recipient spoken", VoiceQuery.recipientAnswer("tana arroba gmail punto com"), "tana@gmail.com")
        check("es contact candidates", VoiceQuery.contactCandidates("mi amigo Enzo"), ["mi amigo Enzo", "Enzo"])
        check("es subject", VoiceQuery.subjectAnswer("el asunto es Reunión del lunes"), "Reunión del lunes")
        check("es no subject", VoiceQuery.subjectAnswer("sin asunto"), "")
        check("es body dile que", VoiceQuery.bodyAnswer("dile que llego tarde").instruction, "llego tarde")
        check("es body literal", VoiceQuery.bodyAnswer("palabra por palabra: nos vemos a las diez").body, "nos vemos a las diez")
        check("es attachment", VoiceQuery.attachmentAnswer("sí, Goku punto png"), "Goku.png")
        check("es looks Spanish", VoiceQuery.textLanguage("dile que la imagen está lista"), .es)
        check("es looks Spanish 2", VoiceQuery.textLanguage("gracias por lo de ayer"), .es)
        check("fr stays French: tu es en retard", VoiceQuery.textLanguage("tu es en retard"), .fr)
        check("fr stays French: réunion à 10h", VoiceQuery.textLanguage("réunion à 10 heures demain"), .fr)
        check("fr stays French: il y a", VoiceQuery.textLanguage("il y a une réunion"), .fr)
        check("en stays English: no", VoiceQuery.textLanguage("I have no time"), .en)
        check("simple mail es", VoiceQuery.simpleMail(from: "dile que la imagen está lista"),
              "Hola,\n\nLa imagen está lista.\n\nUn saludo.")

        // Web search and questions
        check("es web lead", VoiceQuery.webQuery(of: "busca en internet quién ganó la Eurocopa"), "quién ganó la Eurocopa")
        check("es web tail", VoiceQuery.webQuery(of: "busca el horario del Prado en internet"), "el horario del Prado")
        check("es web puedes", VoiceQuery.webQuery(of: "¿Puedes buscar en la web el precio del iPhone 17?"), "el precio del iPhone 17")
        check("es web haz una búsqueda", VoiceQuery.webQuery(of: "haz una búsqueda en internet sobre Tesla"), "Tesla")
        check("es web nothing after", VoiceQuery.webQuery(of: "busca en internet"), "")
        check("es web not: plain search", VoiceQuery.webQuery(of: "busca Daft Punk"), nil)
        check("es web mira", VoiceQuery.webQuery(of: "mira en internet qué hora es en Tokio"), "qué hora es en Tokio")
        check("en web keeps Mira", VoiceQuery.webQuery(of: "search the web for Mira Murati"), "Mira Murati")
        check("es question quién", VoiceQuery.looksLikeQuestion("quién ganó el partido ayer"), true)
        check("es question qué es", VoiceQuery.looksLikeQuestion("qué es un agujero negro"), true)
        check("es question y en", VoiceQuery.looksLikeQuestion("y en Madrid"), false)
        check("es question y en ?", VoiceQuery.looksLikeQuestion("¿y en Madrid?"), true)
        check("es question cuándo", VoiceQuery.looksLikeQuestion("cuándo abre el Prado"), true)
        check("es not a question: que alone", VoiceQuery.looksLikeQuestion("que suene algo de jazz"), false)
        check("es not a question: request", VoiceQuery.looksLikeQuestion("¿puedes poner música?"), false)
        check("es not a question: command", VoiceQuery.looksLikeQuestion("pon algo de Daft Punk"), false)

        // Apps
        check("es abre Figma", VoiceQuery.appToOpen("abre Figma"), "Figma")
        check("es abre la aplicación Notas", VoiceQuery.appToOpen("abre la aplicación Notas"), "Notas")

        // Answers in Spanish
        var es = VoiceSnapshot()
        es.stripe = .init(balance: "1240,00 €", today: "85,00 €", todayCount: 2, last: [])
        contains("es stripe today", VoiceAnswer.text(.stripe, es, lang: .es), "Hoy: 85,00 €, 2 pagos.")
        contains("es stripe balance", VoiceAnswer.text(.stripe, es, lang: .es), "Saldo: 1240,00 €.")
        es.github = .init(stars: 128, repos: 12,
                          myPRs: [.init(title: "a", repo: "r", ci: "failure", review: "pending")],
                          toReview: 1, failingRepos: ["korus"])
        let esGh = VoiceAnswer.text(.github, es, lang: .es)
        contains("es github stars", esGh, "Tienes 128 estrellas en 12 repos.")
        contains("es github PR", esGh, "1 PR abierta, 1 con la CI fallando.")
        contains("es github red", esGh, "La CI de korus está en rojo.")
        es.deploys = [.init(project: "korus", state: "ERROR", ago: "5 minutos", commit: nil)]
        contains("es vercel failed", VoiceAnswer.text(.vercel, es, lang: .es), "El último despliegue de korus ha fallado, hace 5 minutos.")
        es.sessions = [.init(name: "Claude Code", state: "working", detail: "Edit IntentParser.swift")]
        contains("es agents", VoiceAnswer.text(.agents, es, lang: .es), "Claude Code está trabajando: Edit IntentParser.swift.")
        contains("en agents keeps its colon", VoiceAnswer.text(.agents, es, lang: .en), "Claude Code is working : Edit IntentParser.swift.")
        var esOff = VoiceSnapshot(); esOff.configured = false
        contains("es not configured", VoiceAnswer.text(.stripe, esOff, lang: .es), "Stripe no está conectado en los ajustes de Coucou.")
        var esW = VoiceSnapshot()
        esW.weather = .init(city: "Madrid", nowTemp: 21, code: 0, min: 12, max: 24, rainChance: 40, wind: 10)
        contains("es weather now", VoiceAnswer.text(.weatherToday, esW, lang: .es), "En Madrid, 21 grados, cielo despejado. Entre 12 y 24 hoy.")
        contains("es weather rain", VoiceAnswer.text(.weatherToday, esW, lang: .es), "40 % de probabilidad de lluvia.")
        contains("es weather tomorrow", VoiceAnswer.text(.weatherTomorrow, esW, lang: .es), "Mañana en Madrid: cielo despejado, de 12 a 24 grados.")
        esW.weatherOff = true
        contains("es weather off", VoiceAnswer.text(.weatherToday, esW, lang: .es), "Activa el tiempo en los ajustes")
        var esPlan = VoiceSnapshot(); esPlan.plan = .init(fiveHourPct: 40, sevenDayPct: 10, resetsIn: "2 horas")
        contains("es plan", VoiceAnswer.text(.claudePlan, esPlan, lang: .es), "Plan Claude: 40 % en 5 horas y 10 % en la semana. Se reinicia en 2 horas.")
        var esMusic = VoiceSnapshot(); esMusic.nowPlaying = (title: "Malamente", artist: "Rosalía")
        contains("es music", VoiceAnswer.text(.music, esMusic, lang: .es), "Es Malamente, de Rosalía.")
        var esPills = VoiceSnapshot(); esPills.mainPill = "Cursor"; esPills.activePills = ["GitHub"]
        contains("es pills", VoiceAnswer.text(.pills, esPills, lang: .es), "Píldora principal: Cursor. Activas: GitHub.")
        check("es wmo 95", VoiceAnswer.weatherText(95, lang: .es), "tormentas")
        check("es state finished", VoiceAnswer.stateText("finished", lang: .es), "ha terminado")

        // VoiceLang
        check("lang code es-MX", VoiceLang(code: "es-MX"), .es)
        check("lang code fr_CA", VoiceLang(code: "fr_CA"), .fr)
        check("lang code de → en", VoiceLang(code: "de"), .en)
        check("lang code nil → en", VoiceLang(code: nil), .en)
        check("lang supported de", VoiceLang.supported("de-DE"), nil)
        check("lang locale es", VoiceLang.es.localeId, "es-ES")
        check("lang name in es", VoiceLang.fr.name(in: .es), "francés")
        check("lang t", VoiceLang.es.t("a", "b", "c"), "c")

        let total = pass + fail
        if fail == 0 { print("\n\(total)/\(total) passed.") }
        else { print("\n\(fail) FAILED / \(total) total"); exit(1) }
    }
}
