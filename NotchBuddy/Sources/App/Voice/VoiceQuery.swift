#if !APPSTORE
import Foundation

// MARK: - VoiceQuery
//
// Questions about what Coucou already knows ("combien d'étoiles sur GitHub ?",
// "mon déploiement Vercel est passé ?", "quel temps il fait ?") and the two
// requests that are not pill or music commands (prepare an email, open an app).
//
// Pure: no AppKit, no AppState, no network. The Mac side fills a VoiceSnapshot
// (VoiceDataSources.swift) and VoiceAnswer turns it into one or two spoken sentences.
// Answers are French, English or Spanish (the answer language); other languages get English.

enum VoiceTopic: String, Equatable, CaseIterable {
    case stripe, github, vercel, resend, n8n, notion, calcom
    case agents          // Claude Code and the other agent sessions
    case claudePlan, codexPlan
    case music, pills
    case weatherToday, weatherTomorrow
}

enum VoiceQuery {

    // MARK: Detection

    /// The topic of a question, or nil when the phrase is a command or not a question.
    /// A phrase with an action verb ("est-ce que tu peux ajouter GitHub") stays a command.
    static func topic(of raw: String) -> VoiceTopic? {
        let norm  = IntentParser.normalise(raw)
        let words = norm.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        let text  = " " + norm + " "
        func has(_ s: String) -> Bool { text.contains(" " + s + " ") }
        func hasAny(_ list: [String]) -> Bool { list.contains(where: has) }

        if !Set(words).isDisjoint(with: actionVerbs) { return nil }

        let asks = raw.trimmingCharacters(in: .whitespaces).hasSuffix("?")
            || hasAny(questionMarkers)

        // Weather words are clear enough on their own ("météo", "il pleut ?"). Spanish
        // "tiempo" is also "time": only in weather phrases ("qué tiempo hace").
        if hasAny(["meteo", "weather", "quel temps", "il pleut", "va pleuvoir", "pleuvoir",
                   "temperature", "il fait chaud", "il fait froid", "fait il beau", "il fait beau",
                   "forecast", "rain", "parapluie", "umbrella",
                   "que tiempo", "tiempo hace", "tiempo hara", "tiempo va a hacer", "llueve", "va a llover",
                   "llover", "lluvia", "temperatura", "hace calor", "hace frio", "hace sol",
                   "hace buen tiempo", "paraguas", "pronostico"]) {
            return hasAny(["demain", "tomorrow"]) || saysTomorrowES(words) ? .weatherTomorrow : .weatherToday
        }
        guard asks else { return nil }

        // Named services first.
        if has("stripe") { return .stripe }
        if hasAny(["github", "git hub", "gt"]) { return .github }
        if has("vercel") { return .vercel }
        if has("resend") { return .resend }
        if hasAny(["n8n", "n 8 n", "workflow", "workflows", "automatisation", "automatisations",
                   "automatizacion", "automatizaciones"]) { return .n8n }
        if has("notion") { return .notion }
        if hasAny(["cal com", "calcom", "rendez vous", "rdv", "agenda", "reunion", "reunions",
                   "meeting", "meetings", "booking", "bookings", "reservation", "reservations",
                   "cita", "citas", "reserva", "reservas"]) { return .calcom }
        if hasAny(["quota", "limite", "limites", "forfait", "usage", "plan", "cuota"]) {
            return has("codex") ? .codexPlan : .claudePlan
        }
        if hasAny(["claude", "codex", "cursor", "gemini", "copilot", "vs code", "vscode", "visual studio",
                   "agent", "agents",
                   "session", "sessions", "qu est ce qui se passe", "ou en est", "il fait quoi",
                   "what s happening", "whats happening",
                   "agente", "agentes", "sesion", "sesiones", "que esta pasando", "que esta haciendo"]) { return .agents }
        // Generic words.
        if hasAny(["argent", "vendu", "vente", "ventes", "chiffre", "revenu", "revenus", "gagne",
                   "encaisse", "paiement", "paiements", "solde", "money", "sales", "revenue",
                   "earned", "payments", "balance",
                   "dinero", "vendido", "ventas", "ingresos", "facturado", "ganado", "cobrado", "pago",
                   "pagos", "saldo"]) { return .stripe }
        if hasAny(["etoile", "etoiles", "star", "stars", "pull request", "pull requests", "pr", "prs",
                   "repo", "repos", "ci", "estrella", "estrellas", "repositorio", "repositorios"]) { return .github }
        if hasAny(["deploiement", "deploiements", "deploy", "deploye", "deployment", "push", "pousse",
                   "despliegue", "despliegues", "desplegado"]) { return .vercel }
        // Generic "mails" means Resend stats only when asking about sent mail.
        if hasAny(["mail", "mails", "email", "emails", "correo", "correos"]),
           hasAny(["combien", "how many", "derniers", "dernier", "last", "envoyes", "envoye", "sent", "delivres", "delivered",
                   "cuantos", "ultimos", "ultimo", "enviados", "enviado", "entregados"]) {
            return .resend
        }
        if hasAny(["chanson", "musique", "titre", "morceau", "song", "track", "playing", "ecoute",
                   "cancion", "musica", "suena", "sonando"]) { return .music }
        if hasAny(["pilule", "pilules", "pill", "pills", "pildora", "pildoras"]) { return .pills }
        return nil
    }

    /// Spanish "mañana" is "tomorrow", but "esta mañana" / "por la mañana" is "this morning".
    private static func saysTomorrowES(_ words: [String]) -> Bool {
        words.indices.contains { i in
            words[i] == "manana" && (i == 0 || !["esta", "la"].contains(words[i - 1]))
        }
    }

    // Spanish "que" alone is also "that": only in question phrases ("qué tal", "qué hay").
    private static let questionMarkers = [
        "combien", "quel", "quelle", "quels", "quelles", "est ce", "c est quoi", "qu est ce",
        "ou en", "comment", "dis moi", "donne moi", "montre moi", "y a t il", "il y a",
        "how", "what", "whats", "did", "is", "are", "any", "tell me", "show me", "statut", "status",
        "etat", "est il", "est elle", "a t il", "a t elle",
        "cuanto", "cuanta", "cuantos", "cuantas", "cual", "cuales", "que tal", "que hay", "que pasa",
        "que es", "como va", "como van", "como esta", "como estan", "dime", "muestrame", "ensename",
        "hay", "ha", "han", "tengo", "esta", "estan", "estado",
    ]

    private static let actionVerbs: Set<String> = [
        "ajoute", "ajouter", "ajoutes", "rajoute", "enleve", "enlever", "enleves", "retire", "retirer",
        "supprime", "supprimer", "mets", "mettre", "met", "lance", "lancer", "joue", "jouer",
        "remplace", "remplacer", "active", "activer", "desactive", "vire", "virer",
        "envoie", "envoyer", "envoies", "ecris", "ecrire", "redige", "rediger", "ouvre", "ouvrir",
        "add", "remove", "play", "open", "send", "write", "compose", "draft", "email",
        "anade", "anadir", "agrega", "agregar", "pon", "poner", "ponme", "quita", "quitar", "quitame",
        "elimina", "eliminar", "borra", "borrar", "activa", "activar", "desactiva", "desactivar",
        "reproducir", "envia", "enviar", "manda", "mandar", "escribe", "escribir",
        "redacta", "redactar", "abre", "abrir", "reemplaza",
    ]

    // MARK: Email
    //
    //   "envoie un mail à Tana"
    //   "envoie le fichier facture octobre des téléchargements à Tana"
    //   "il y a une image qui s'appelle Goku.png, envoie-la par mail à tana@gmail.com.
    //    En objet, tu écris : Voilà votre image. En description : Image en 1980 × 1080."
    //   "email the image called Goku.png to tana@gmail.com, subject Here you go, body …"
    //   "write an email to Tana thanking her for yesterday"   (instruction → Coucou drafts)
    //   "envía la imagen que se llama Goku.png a tana@gmail.com con el asunto Aquí tienes"

    struct MailRequest: Equatable {
        var recipient: String
        var file: String?
        var folder: Folder?
        var subject: String? = nil
        var body: String? = nil
        /// What the mail should say when no body was dictated ("thanking her…"):
        /// Coucou drafts the body from it.
        var instruction: String? = nil
        enum Folder: String, Equatable { case downloads, desktop, documents, pictures }
    }

    private static let sendVerbs: Set<String> = [
        "envoie", "envoyer", "envoies", "envoyes", "ecris", "ecrire", "ecrit", "redige", "rediger",
        "send", "email", "mail", "write", "compose", "draft",
        "envia", "enviar", "envies", "manda", "mandar", "mandes", "escribe", "escribir", "escribas",
        "redacta", "redactar",
    ]
    private static let mailWords: Set<String> = ["mail", "email", "mel", "courriel", "emails", "mails",
                                                 "correo", "correos"]
    private static let fileWords: Set<String> = ["fichier", "image", "photo", "document", "pdf", "file",
                                                 "picture", "screenshot", "capture", "video",
                                                 "archivo", "fichero", "imagen", "foto", "documento", "captura"]
    private static let subjectMarkers = ["en objet", "comme objet", "avec l'objet", "avec pour objet", "objet",
                                         "en titre", "sujet", "with the subject", "subject", "titled",
                                         "con el asunto", "con asunto", "como asunto", "de asunto", "asunto"]
    private static let bodyMarkers = ["en description", "description", "corps du mail", "en texte", "avec le texte",
                                      "pour lui dire que", "pour lui dire", "pour dire que", "en disant que",
                                      "en disant", "qui dit", "with the text", "body", "saying that", "saying",
                                      "that says", "to say that", "to say", "telling",
                                      "con el texto", "con el mensaje", "en el cuerpo", "que diga",
                                      "para decirle que", "para decirle", "para decir que",
                                      "diciendole que", "diciendole", "diciendo que", "diciendo"]
    /// Markers after which the text is what the mail is about, for Coucou to write it
    /// ("pour lui dire que l'image est prête"); the others dictate the exact text.
    private static let instructionMarkers: Set<String> = ["pour lui dire que", "pour lui dire", "pour dire que",
                                                          "en disant que", "en disant", "saying that", "saying",
                                                          "to say that", "to say", "telling",
                                                          "para decirle que", "para decirle", "para decir que",
                                                          "diciendole que", "diciendole", "diciendo que", "diciendo"]

    static func mail(of raw: String) -> MailRequest? {
        // 1. Subject and body are free text: cut them out of the raw string first.
        let subj = firstMarker(subjectMarkers, in: raw)
        let body = firstMarker(bodyMarkers, in: raw)
        let cut  = [subj?.range.lowerBound, body?.range.lowerBound].compactMap { $0 }.min() ?? raw.endIndex
        let head = String(raw[..<cut])
        func segment(_ m: (range: Range<String.Index>, marker: String)?, other: (range: Range<String.Index>, marker: String)?) -> String? {
            guard let m else { return nil }
            var end = raw.endIndex
            if let o = other, o.range.lowerBound > m.range.lowerBound { end = o.range.lowerBound }
            return cleanFreeText(String(raw[m.range.upperBound..<end]))
        }
        let subject = segment(subj, other: body)
        let bodySegment = segment(body, other: subj)
        let bodyIsInstruction = body.map { instructionMarkers.contains($0.marker) } ?? false
        let bodyText = bodyIsInstruction ? nil : bodySegment

        // 2. Verb, recipient, file and folder from the head.
        let n = IntentParser.normalise(head).split(separator: " ").map(String.init)
        let r = rawWords(head)
        guard n.count == r.count, !n.isEmpty,
              let v = n.firstIndex(where: { sendVerbs.contains($0) }) else { return nil }
        let isMail = n.contains(where: { mailWords.contains($0) }) || ["email", "mail"].contains(n[v])
        guard isMail || n.contains(where: { fileWords.contains($0) }) else { return nil }

        // No "à / to": a guided mail — Coucou asks who, the subject, the text, an attachment.
        guard let to = n.lastIndex(where: { $0 == "a" || $0 == "to" }), to > v, to + 1 < n.count else {
            guard isMail else { return nil }
            return MailRequest(recipient: "", file: nil, folder: nil, subject: subject, body: bodyText,
                               instruction: bodyIsInstruction ? bodySegment : nil)
        }
        let after = Array(r[(to + 1)...])
        var recipientWords: [String] = []
        var rest: [String] = []
        if let first = after.first, first.contains("@") || isSpelledEmail(after) {
            let joined = after.joined(separator: " ")
            recipientWords = [joined]
        } else {
            // A contact name: the capitalised words right after "à" (or just the first one).
            for (i, w) in after.enumerated() {
                if i == 0 || (w.first?.isUppercase == true && rest.isEmpty) { recipientWords.append(w) }
                else { rest = Array(after[i...]); break }
            }
        }
        var recipient = recipientWords.joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if let email = spokenEmail(recipient) { recipient = email }
        guard !recipient.isEmpty else { return nil }

        var folder: MailRequest.Folder? = nil
        if n.contains(where: { ["telechargements", "telechargement", "downloads", "descargas"].contains($0) }) { folder = .downloads }
        else if n.contains(where: { ["bureau", "desktop", "escritorio"].contains($0) }) { folder = .desktop }
        else if n.contains(where: { ["documents", "documentos"].contains($0) }) { folder = .documents }
        else if n.contains(where: { ["photos", "images", "pictures", "fotos", "imagenes"].contains($0) }) { folder = .pictures }

        var file: String? = nil
        if let f = n.firstIndex(where: { fileWords.contains($0) }) {
            let skip: Set<String> = ["qui", "s", "appelle", "appellent", "appelee", "appele", "nommee", "nomme",
                                     "called", "named", "la", "le", "l", "the", "mon", "ma", "my", "intitule", "intitulee",
                                     "llama", "llaman", "llamado", "llamada", "el", "mi"]
            let stop: Set<String> = ["des", "du", "de", "dans", "from", "in", "par", "en", "a", "to", "et", "and",
                                     "pour", "que", "qu", "j", "je", "sur", "on", "mes", "my", "telechargements",
                                     "telechargement", "downloads", "bureau", "desktop", "documents", "photos", "pictures",
                                     "del", "por", "para", "y", "descargas", "escritorio", "documentos", "fotos"]
            var i = f + 1
            while i < n.count {
                // Spanish "la imagen que se llama Goku": "que se" names the file, "que" alone ends it.
                if n[i] == "que", i + 1 < n.count, n[i + 1] == "se" { i += 2 }
                else if skip.contains(n[i]) { i += 1 }
                else { break }
            }
            var parts: [String] = []
            while i < n.count, !(stop.contains(n[i]) && !parts.isEmpty) {
                if ["point", "dot", "punto"].contains(n[i]), i + 1 < n.count, ["png", "jpg", "jpeg", "pdf", "heic", "gif", "mov", "mp4", "docx", "zip", "txt"].contains(n[i + 1]) {
                    if let last = parts.popLast() { parts.append(last + "." + n[i + 1]) }
                    i += 2; continue
                }
                if stop.contains(n[i]) { break }
                parts.append(r[i].trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")))
                i += 1
            }
            let name = parts.joined(separator: " ")
            if !name.isEmpty { file = name } else if n[f] == "pdf" { file = "pdf" }
        }

        var instruction: String? = bodyIsInstruction ? bodySegment : nil
        if bodyText == nil && instruction == nil {
            let extra = rest.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if !extra.isEmpty { instruction = extra }
        }
        return MailRequest(recipient: recipient, file: file, folder: folder,
                           subject: subject, body: bodyText, instruction: instruction)
    }

    // MARK: Guided email answers

    /// "c'est Tana", "à tana arobase gmail point com", "send it to Paul" → "Tana" / "tana@gmail.com" / "Paul".
    static func recipientAnswer(_ raw: String) -> String {
        var t = stripLead(raw, ["envoie le à", "envoie-le à", "envoie la à", "envoie-la à", "send it to", "it's for",
                                "il s'appelle", "elle s'appelle", "ils s'appellent", "elles s'appellent", "s'appelle",
                                "son nom c'est", "son nom est", "son prénom c'est", "son prénom est", "son mail c'est",
                                "son adresse c'est", "son adresse mail c'est", "son email c'est", "mon ami", "mon amie",
                                "mon pote", "ma pote", "mon frère", "ma sœur", "ma soeur",
                                "his name is", "her name is", "their name is", "the name is", "name is",
                                "his email is", "her email is", "it's called", "called",
                                "envíaselo a", "envíalo a", "envíala a", "mándaselo a", "mándalo a", "mándala a",
                                "se llama", "su nombre es", "su correo es", "su email es", "su dirección es",
                                "es para", "mi amigo", "mi amiga", "mi colega", "mi hermano", "mi hermana", "es", "para",
                                "c'est pour", "c'est", "c est", "it's", "its", "to", "à", "a", "pour", "for", "the", "le", "la"])
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?"))
        return spokenEmail(t) ?? t
    }

    /// "image image" → "image", "Paul Dupont Paul Dupont" → "Paul Dupont": an answer said
    /// twice in the same turn (the first time looked unheard) counts once.
    static func collapseRepeat(_ raw: String) -> String {
        let words = raw.split(separator: " ").map(String.init)
        guard words.count >= 2, words.count % 2 == 0 else { return raw }
        let half = words.count / 2
        let a = IntentParser.normalise(words[..<half].joined(separator: " "))
        let b = IntentParser.normalise(words[half...].joined(separator: " "))
        return a == b && !a.isEmpty ? words[..<half].joined(separator: " ") : raw
    }

    /// Names to try in the contacts for a spoken recipient: the whole of it, then its
    /// capitalised words, then each word ("le pote Enzo" → "Enzo").
    static func contactCandidates(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return [] }
        let words = trimmed.split(separator: " ").map(String.init)
        let stop: Set<String> = ["le", "la", "les", "l", "de", "du", "des", "mon", "ma", "mes", "ami", "amie", "pote",
                                 "c", "est", "il", "elle", "s", "appelle", "the", "my", "friend", "is", "name", "his",
                                 "her", "a", "à", "et", "and",
                                 "el", "mi", "mis", "amigo", "amiga", "llama", "su", "nombre"]
        var out = [trimmed]
        let caps = words.filter { $0.first?.isUppercase == true && !stop.contains(IntentParser.normalise($0)) }
        if !caps.isEmpty { out.append(caps.joined(separator: " ")) }
        for w in words.reversed() where w.count >= 2 && !stop.contains(IntentParser.normalise(w)) { out.append(w) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.lowercased()).inserted }
    }

    /// "l'objet c'est Voilà votre image" → "Voilà votre image"; "pas d'objet" / "no subject" → "".
    static func subjectAnswer(_ raw: String) -> String {
        let n = IntentParser.normalise(raw)
        if ["pas d objet", "aucun objet", "sans objet", "no subject", "none", "rien", "nothing", "pas d objet merci",
            "sin asunto", "ningun asunto", "no hay asunto", "nada", "ninguno"].contains(n) { return "" }
        return stripLead(raw, ["l'objet c'est", "l'objet est", "l'objet", "objet", "en objet", "the subject is", "subject is",
                               "subject", "c'est", "it's", "mets", "put", "write",
                               "el asunto es", "el asunto", "asunto", "pon", "escribe", "es"])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?\"«»“”"))
    }

    /// One rule, always the same: Coucou writes the mail from what I say ("faut dire que
    /// l'image est prête" → a short mail saying it). Only "mot pour mot / exactement /
    /// word for word …" dictates the exact text.
    static func bodyAnswer(_ raw: String) -> (body: String?, instruction: String?) {
        let literalLeads = ["mot pour mot", "texte exact", "le texte exact c'est", "écris exactement", "ecris exactement",
                            "exactement", "word for word", "verbatim", "exactly", "write exactly", "the exact text is",
                            "palabra por palabra", "textualmente", "literalmente", "escribe exactamente", "exactamente",
                            "el texto exacto es"]
        let literal = stripLead(raw, literalLeads)
        if literal.count < raw.trimmingCharacters(in: .whitespacesAndNewlines).count {
            return (literal.trimmingCharacters(in: CharacterSet(charactersIn: " :;\"«»“”")), nil)
        }
        let what = instructionText(raw)
        return (nil, what.isEmpty ? raw : what)
    }

    /// What the mail should say, without the way I asked: "faut dire que l'image est prête",
    /// "écris-lui que…", "tell her that…" → "l'image est prête" / "…".
    static func instructionText(_ raw: String) -> String {
        stripLead(raw, ["il faut lui dire que", "il faut dire que", "faut lui dire que", "faut dire que", "faut lui dire",
                        "faut dire", "il faut dire", "écris-lui un message pour lui dire que", "écris-lui un message pour lui dire",
                        "écris-lui pour lui dire que", "écris-lui pour lui dire", "écris-lui que", "écris-lui", "écris lui",
                        "écris un message pour lui dire que", "écris un message pour lui dire", "écris que", "écris", "ecris",
                        "rédige-lui", "rédige", "dis-lui que", "dis-lui", "dis lui que", "dis lui", "dites-lui que",
                        "pour lui dire que", "pour lui dire", "pour dire que", "dire que", "que", "préviens-la que",
                        "préviens-le que", "préviens-la", "préviens-le", "le message c'est", "le message", "c'est",
                        "write her that", "write him that", "write them that", "write that", "write", "tell her that",
                        "tell him that", "tell them that", "tell her", "tell him", "tell them", "say that", "say",
                        "let her know that", "let him know that", "let them know that", "draft", "the message is", "that",
                        "tienes que decirle que", "hay que decirle que", "hay que decir que", "dile que", "dile",
                        "escríbele que", "escríbele", "escribe que", "escribe", "pon que", "para decirle que",
                        "para decirle", "avísale de que", "avísale que", "avísale", "el mensaje es", "el mensaje"])
            .trimmingCharacters(in: CharacterSet(charactersIn: " :;\"«»“”"))
    }

    /// The language the instruction is in (to write the mail in the same language).
    /// Spanish shares many short words with French: it wins only with more of its own
    /// words than French and English; otherwise French beats English as before.
    static func textLanguage(_ s: String) -> VoiceLang {
        let words = IntentParser.normalise(s).split(separator: " ").map(String.init)
        let fr: Set<String> = ["le", "la", "les", "l", "que", "qu", "est", "sont", "de", "des", "du", "pour", "je", "tu",
                               "il", "elle", "nous", "vous", "un", "une", "et", "a", "au", "avec", "pas", "prete", "pret",
                               "merci", "demain", "hier", "bien", "c", "ce", "sa", "son", "ton", "ta", "mon", "ma"]
        let en: Set<String> = ["the", "is", "are", "that", "to", "of", "for", "i", "you", "he", "she", "we", "and",
                               "with", "not", "ready", "thanks", "thank", "tomorrow", "yesterday", "it", "my", "your"]
        // Words French or English use too ("la", "que", "y", "son"…) count for Spanish, but it also
        // needs two of its own: "play Los Lobos" or "no subject" stay English.
        let shared: Set<String> = ["la", "un", "que", "de", "a", "y", "son", "bien"]
        let esOnly: Set<String> = ["el", "los", "las", "lo", "una", "del", "es", "esta", "estan", "estoy", "para",
                                   "por", "con", "sin", "yo", "mi", "su", "ella", "nos", "nosotros", "lista", "listo",
                                   "listos", "gracias", "manana", "ayer", "hoy", "muy", "pero", "hay", "ya", "llego",
                                   "tarde"]
        let f = words.filter { fr.contains($0) }.count
        let e = words.filter { en.contains($0) }.count
        let own = words.filter { esOnly.contains($0) }.count
        let x = own + words.filter { shared.contains($0) }.count
        if own >= 2 && x > f && x > e { return .es }
        return f > e ? .fr : .en
    }

    /// A plain mail from the instruction when no model can write it: "l'image est prête"
    /// → "Bonjour,\n\nL'image est prête.\n\nBonne journée !"
    static func simpleMail(from instruction: String) -> String {
        var t = instructionText(instruction).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return instruction }
        t = first.uppercased() + t.dropFirst()
        if let last = t.last, !".!?".contains(last) { t += "." }
        return textLanguage(instruction).t("Bonjour,\n\n\(t)\n\nBonne journée !", "Hi,\n\n\(t)\n\nBest,",
                                           "Hola,\n\n\(t)\n\nUn saludo.")
    }

    /// "oui, Goku.png" / "yes the file called invoice" → "Goku.png" / "invoice"; nil for "no".
    static func attachmentAnswer(_ raw: String) -> String? {
        var t = stripLead(raw, ["oui", "ouais", "yes", "yeah", "c'est", "it's", "le fichier qui s'appelle", "l'image qui s'appelle",
                                "le fichier", "l'image", "la photo", "the file called", "the image called", "the file", "the image",
                                "attach", "joins", "joint",
                                "sí", "vale", "es", "el archivo que se llama", "la imagen que se llama", "el archivo",
                                "la imagen", "la foto", "adjunta", "adjunto"])
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:!?"))
        if t.hasSuffix(".") && !t.dropLast().contains(".") { t.removeLast() }
        // "goku point png" → "goku.png"
        for ext in ["png", "jpg", "jpeg", "pdf", "heic", "gif", "mov", "mp4", "docx", "zip", "txt"] {
            t = t.replacingOccurrences(of: " point \(ext)", with: ".\(ext)", options: .caseInsensitive)
                 .replacingOccurrences(of: " dot \(ext)", with: ".\(ext)", options: .caseInsensitive)
                 .replacingOccurrences(of: " punto \(ext)", with: ".\(ext)", options: .caseInsensitive)
        }
        return t.isEmpty ? nil : t
    }

    /// Drops the first matching lead phrase (case/diacritic-insensitive, whole words), repeatedly.
    static func stripLead(_ raw: String, _ leads: [String]) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,:;-–—").union(.whitespaces))
            for l in leads.sorted(by: { $0.count > $1.count }) {
                guard let r = t.range(of: l, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else { continue }
                if r.upperBound == t.endIndex || !t[r.upperBound].isLetter {
                    t = String(t[r.upperBound...]); changed = true; break
                }
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "tana arobase gmail point com" / "tana at gmail dot com" / "tana arroba gmail punto com"
    /// / "tana@gmail.com." → "tana@gmail.com".
    static func spokenEmail(_ s: String) -> String? {
        var t = " " + s.lowercased() + " "
        for (a, b) in [(" arobase ", "@"), (" at ", "@"), (" point ", "."), (" dot ", "."), (" tiret ", "-"),
                       (" underscore ", "_"), (" dash ", "-"), (" arroba ", "@"), (" punto ", "."),
                       (" guion bajo ", "_"), (" guión bajo ", "_"), (" guion ", "-"), (" guión ", "-")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        let ok = t.range(of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
        return ok ? t : nil
    }

    private static func isSpelledEmail(_ words: [String]) -> Bool {
        let n = words.map { IntentParser.normalise($0) }
        return n.contains("arobase") || n.contains("arroba")
            || (n.contains("at") && (n.contains("dot") || n.contains("point")))
    }

    private static func firstMarker(_ markers: [String], in raw: String) -> (range: Range<String.Index>, marker: String)? {
        var best: (range: Range<String.Index>, marker: String)? = nil
        for m in markers {
            var from = raw.startIndex
            while let r = raw.range(of: m, options: [.caseInsensitive, .diacriticInsensitive], range: from..<raw.endIndex) {
                // Whole words only.
                let beforeOK = r.lowerBound == raw.startIndex || !raw[raw.index(before: r.lowerBound)].isLetter
                let afterOK  = r.upperBound == raw.endIndex || !raw[r.upperBound].isLetter
                if beforeOK && afterOK {
                    if best == nil || r.lowerBound < best!.range.lowerBound
                        || (r.lowerBound == best!.range.lowerBound && r.upperBound > best!.range.upperBound) {
                        best = (r, m)
                    }
                    break
                }
                from = r.upperBound
            }
        }
        return best
    }

    /// ": tu écris : Voilà votre image." → "Voilà votre image"
    private static func cleanFreeText(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = ["tu écris", "tu ecris", "tu mets", "écris", "ecris", "mets", "write", "put", "it's", "is", "c'est", "ce sera",
                    "escribes", "escribe", "pones", "pon", "será", "sera", "es"]
        var changed = true
        while changed {
            changed = false
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: " :,;-–—\"«»“”").union(.whitespaces))
            for l in lead where t.lowercased().hasPrefix(l + " ") || t.lowercased().hasPrefix(l + ":") || t.lowercased() == l {
                t = String(t.dropFirst(l.count)); changed = true; break
            }
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .,;\"«»“”").union(.whitespacesAndNewlines))
        for tail in [" et", " and", " puis", " y", " luego"] where t.lowercased().hasSuffix(tail) { t = String(t.dropLast(tail.count)) }
        return t.isEmpty ? nil : t
    }

    // MARK: Web search: "cherche sur internet qui a gagné hier", "search the web for…"

    /// The question in an explicit web search, "" when nothing follows ("cherche sur
    /// internet"), nil when the phrase is not a web search. Leading and trailing words
    /// ("cherche", "sur internet", "for me"…) are removed; the rest keeps its spelling.
    static func webQuery(of raw: String) -> String? {
        let toks = tokens(raw)
        let n = toks.map { $0.norm }
        guard !n.isEmpty else { return nil }
        let joined = " " + n.joined(separator: " ") + " "
        let webWords = [" internet ", " web ", " google ", " googler ", " en ligne ", " online ", " look up ", " look it up ",
                        " en linea "]
        guard webWords.contains(where: { joined.contains($0) }) else { return nil }
        let verbs: Set<String> = ["cherche", "cherches", "chercher", "recherche", "recherches", "rechercher",
                                  "regarde", "regardes", "regarder", "trouve", "trouves", "trouver",
                                  "search", "look", "find", "check", "fais", "faire",
                                  "busca", "buscas", "buscar", "buscame", "mira", "mirar", "encuentra", "encontrar",
                                  "averigua", "averiguar", "consulta", "consultar", "haz", "hazme", "hacer"]
        // "Google" is a verb only first ("Google the weather…"), not in "ouvre Google Chrome".
        guard n.contains(where: { verbs.contains($0) }) || ["google", "googler"].contains(n[0]) else { return nil }

        let heads: [[String]] = [
            ["est", "ce", "que", "tu", "pourrais"], ["est", "ce", "que", "tu", "peux"], ["je", "veux", "que", "tu"],
            ["i", "want", "you", "to"], ["tu", "pourrais"], ["pourrais", "tu"], ["tu", "peux"], ["peux", "tu"],
            ["can", "you"], ["could", "you"], ["would", "you"],
            ["ok"], ["okay"], ["coucou"], ["hey"], ["dis"], ["alors"], ["bon"], ["euh"], ["please"], ["stp"],
            ["fais", "moi", "une", "recherche"], ["fais", "une", "recherche"], ["faire", "une", "recherche"],
            ["fais", "des", "recherches"], ["do", "a", "web", "search"], ["do", "a", "search"],
            ["recherche", "internet"], ["recherche"], ["recherches"], ["rechercher"],
            ["cherche", "moi"], ["cherche"], ["cherches"], ["chercher"], ["regarde"], ["regardes"], ["regarder"],
            ["trouve", "moi"], ["trouve"], ["trouver"], ["search"], ["look", "it", "up"], ["look", "up"],
            ["google"], ["googler"], ["find", "out"], ["find"], ["check"],
            ["sur", "internet"], ["sur", "le", "web"], ["sur", "google"], ["en", "ligne"], ["internet"],
            ["on", "the", "internet"], ["on", "the", "web"], ["the", "internet"], ["the", "web"], ["online"],
            ["on", "google"], ["le", "web"],
            ["des", "informations", "sur"], ["des", "infos", "sur"], ["infos", "sur"], ["information", "about"],
            ["info", "about"], ["info", "on"], ["for", "me"], ["pour", "moi"], ["moi"], ["me"], ["for"],
            ["about"], ["sur"],
            ["me", "puedes"], ["me", "podrias"], ["puedes"], ["podrias"], ["quiero", "que"], ["oye"], ["vale"],
            ["bueno"], ["por", "favor"], ["porfa"], ["hazme", "una", "busqueda"], ["haz", "una", "busqueda"],
            ["buscame"], ["busca"], ["buscas"], ["buscar"], ["encuentra"], ["encontrar"],
            ["averigua"], ["averiguar"], ["consulta"], ["consultar"],
            ["en", "internet"], ["por", "internet"], ["en", "la", "web"], ["en", "google"], ["en", "linea"],
            ["informacion", "sobre"], ["info", "sobre"], ["para", "mi"], ["sobre"],
        ]
        let tails: [[String]] = [
            // Spanish first: "en internet" before the bare "internet" below.
            ["en", "internet"], ["por", "internet"], ["en", "la", "web"], ["en", "google"], ["en", "linea"],
            ["por", "favor"], ["porfa"], ["para", "mi"], ["gracias"],
            ["sur", "internet"], ["sur", "le", "web"], ["sur", "google"], ["en", "ligne"], ["on", "the", "internet"],
            ["on", "the", "web"], ["on", "internet"], ["on", "google"], ["online"], ["internet"],
            ["s", "il", "te", "plait"], ["s", "il", "vous", "plait"], ["stp"], ["please"], ["pour", "moi"],
            ["for", "me"], ["merci"], ["thanks"], ["thank", "you"],
        ]
        // Spanish "mira" only as the first word: "search the web for Mira Murati" keeps "Mira".
        var h = ["mira", "mirar"].contains(n[0]) ? 1 : 0, t = n.count
        var changed = true
        while changed && h < t {
            changed = false
            for seq in heads where h + seq.count <= t && Array(n[h..<(h + seq.count)]) == seq {
                h += seq.count; changed = true; break
            }
            for seq in tails where t - seq.count >= h && Array(n[(t - seq.count)..<t]) == seq {
                t -= seq.count; changed = true; break
            }
        }
        guard h < t else { return "" }
        return String(raw[toks[h].range.lowerBound..<toks[t - 1].range.upperBound])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// A question rather than a command: "qui a gagné hier ?", "what's the capital of…",
    /// "c'est quoi…". Requests ("tu peux…", "can you…") are not questions.
    static func looksLikeQuestion(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var n = IntentParser.normalise(trimmed).split(separator: " ").map(String.init)
        while let f = n.first, n.count > 1,
              ["ok", "okay", "coucou", "hey", "alors", "bon", "euh", "et", "and", "so", "mais", "but",
               "vale", "bueno", "pues", "oye", "y", "pero", "entonces"].contains(f) {
            n.removeFirst()
        }
        guard let first = n.first else { return false }
        let joined = n.joined(separator: " ")
        let requests = ["tu peux", "peux tu", "est ce que tu peux", "est ce que tu pourrais", "tu pourrais",
                        "pourrais tu", "can you", "could you", "would you", "will you", "please",
                        "puedes", "podrias", "me puedes", "me podrias", "por favor", "quiero que"]
        if requests.contains(where: { joined == $0 || joined.hasPrefix($0 + " ") }) { return false }
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("？") { return true }
        // Spanish "que" alone is also "that": only in question phrases ("qué es…").
        let starters: Set<String> = ["what", "who", "when", "where", "why", "how", "which", "whose",
                                     "is", "are", "was", "were", "does", "did",
                                     "qui", "quoi", "quand", "pourquoi", "comment", "combien",
                                     "quel", "quelle", "quels", "quelles", "explain", "explique", "raconte",
                                     "quien", "quienes", "cuando", "donde", "como", "cuanto", "cuanta", "cuantos",
                                     "cuantas", "cual", "cuales", "hay", "explica", "explicame", "cuentame"]
        if starters.contains(first) { return true }
        let phrases = ["qu est ce", "c est quoi", "c est qui", "est ce que", "est ce qu", "tell me", "dis moi",
                       "parle moi", "ou est", "ou sont", "ou se", "ou en est",
                       "por que", "que es", "que son", "que significa", "que hora", "que tal", "que paso",
                       "que pasa", "que tiempo", "a que", "en que", "de que", "dime", "hablame de", "sabes"]
        return phrases.contains(where: { joined == $0 || joined.hasPrefix($0 + " ") })
    }

    /// Text Coucou can say aloud: no markdown, links, URLs, citation marks or bullets.
    static func spokenText(_ s: String) -> String {
        var t = s
        func sub(_ pattern: String, _ with: String) {
            t = t.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        sub(#"\[([^\]]+)\]\((?:[^)]*)\)"#, "$1")         // [text](url) → text
        sub(#"https?://\S+"#, "")                          // bare URLs
        sub(#"\[\d+(?:,\s*\d+)*\]"#, "")                // [1], [2, 3]
        sub(#"(?m)^\s{0,3}#{1,6}\s*"#, "")                 // headings
        sub(#"(?m)^\s*(?:[-*•]|\d+[.)])\s+"#, "")          // bullets, numbered lists
        sub(#"\*\*|__|\*|`"#, "")                          // bold, italics, code
        sub(#"\s*\n+\s*"#, " ")
        sub(#"\s{2,}"#, " ")
        sub(#"\s+([.,;:!?])"#, "$1")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Words of `raw` split like IntentParser.normalise, each with its normalised form and
    /// its range in `raw` (to cut the original text, apostrophes and accents kept).
    static func tokens(_ raw: String) -> [(norm: String, range: Range<String.Index>)] {
        var out: [(norm: String, range: Range<String.Index>)] = []
        var start: String.Index? = nil
        var i = raw.startIndex
        func close(_ end: String.Index) {
            guard let s = start else { return }
            let norm = IntentParser.normalise(String(raw[s..<end]))
            if !norm.isEmpty { out.append((norm, s..<end)) }
            start = nil
        }
        while i < raw.endIndex {
            let c = raw[i]
            if c == " " || c == "'" || c == "\u{2019}" || c == "-" || c.isNewline { close(i) }
            else if start == nil { start = i }
            i = raw.index(after: i)
        }
        close(raw.endIndex)
        return out
    }

    // MARK: Open an app: "ouvre Figma", "open Safari", "abre Notas"

    static func appToOpen(_ raw: String) -> String? {
        let n = IntentParser.normalise(raw).split(separator: " ").map(String.init)
        let r = rawWords(raw)
        guard n.count == r.count,
              let i = n.firstIndex(where: { ["ouvre", "ouvrir", "open", "abre", "abrir", "abreme"].contains($0) }),
              i + 1 < n.count else { return nil }
        var start = i + 1
        while start < n.count, ["moi", "l", "la", "le", "app", "application", "the", "appli",
                                "el", "aplicacion"].contains(n[start]) { start += 1 }
        guard start < n.count else { return nil }
        let name = r[start...].joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        return name.isEmpty ? nil : name
    }

    /// Same splits as IntentParser.normalise, original casing kept, one entry per word.
    static func rawWords(_ raw: String) -> [String] {
        var s = raw
        for c in ["'", "\u{2019}", "-"] { s = s.replacingOccurrences(of: c, with: " ") }
        return s.split(separator: " ").map(String.init).filter { w in
            !IntentParser.normalise(w).isEmpty
        }
    }
}

// MARK: - Snapshot (filled on the Mac side)

struct VoiceSnapshot {
    struct Payment { var amount: String; var description: String?; var ago: String; var succeeded: Bool }
    struct Stripe {
        var balance: String            // "1 240,00 €"
        var today: String?             // nil when the day total could not be fetched
        var todayCount: Int = 0
        var last: [Payment] = []
    }
    struct PR { var title: String; var repo: String; var ci: String; var review: String }
    struct GitHub {
        var stars: Int?; var repos: Int?
        var myPRs: [PR] = []; var toReview: Int = 0; var failingRepos: [String] = []
    }
    struct Deploy { var project: String; var state: String; var ago: String; var commit: String? }
    struct Session { var name: String; var state: String; var detail: String? }
    struct Plan { var fiveHourPct: Int?; var sevenDayPct: Int?; var resetsIn: String? }
    struct Booking { var title: String; var when: String; var with: String? }
    struct Weather {
        var city: String
        var nowTemp: Int?; var code: Int
        var min: Int; var max: Int; var rainChance: Int?; var wind: Int?
    }

    var configured: Bool = true          // false → "<service> n'est pas connecté"
    var stripe: Stripe?
    var github: GitHub?
    var deploys: [Deploy] = []
    var emailsTotal: Int?; var emails: [(to: String, subject: String, state: String)] = []
    var runs: [(workflow: String, ok: Bool, ago: String)] = []
    var pages: [(title: String, ago: String)] = []
    var bookings: [Booking] = []
    var sessions: [Session] = []
    var approvalPending: String?         // tool waiting for approval
    var plan: Plan?
    var nowPlaying: (title: String, artist: String?)?
    var mainPill: String?; var activePills: [String] = []
    var weather: Weather?
    var weatherOff = false               // feature disabled in Settings
    var weatherNoCity = false
}

// MARK: - Answers

enum VoiceAnswer {

    static func text(_ topic: VoiceTopic, _ s: VoiceSnapshot, lang: VoiceLang) -> String {
        func t(_ f: String, _ e: String, _ x: String) -> String { lang.t(f, e, x) }
        if !s.configured {
            return t("\(serviceName(topic)) n'est pas connecté dans les réglages de Coucou.",
                     "\(serviceName(topic)) isn't connected in Coucou's settings.",
                     "\(serviceName(topic)) no está conectado en los ajustes de Coucou.")
        }
        switch topic {
        case .stripe:
            guard let st = s.stripe else {
                return t("Je n'ai pas encore les données Stripe.", "I don't have Stripe data yet.",
                         "Todavía no tengo los datos de Stripe.")
            }
            var out: String
            if let today = st.today {
                let plural = st.todayCount > 1 ? "s" : ""
                out = st.todayCount == 0
                    ? t("Aucune vente aujourd'hui pour l'instant.", "No sales yet today.", "Aún no hay ventas hoy.")
                    : t("Aujourd'hui : \(today), \(st.todayCount) paiement\(plural).",
                        "Today: \(today) from \(st.todayCount) payment\(plural).",
                        "Hoy: \(today), \(st.todayCount) pago\(plural).")
                out += t(" Solde : \(st.balance).", " Balance: \(st.balance).", " Saldo: \(st.balance).")
            } else {
                out = t("Ton solde Stripe est de \(st.balance).", "Your Stripe balance is \(st.balance).",
                        "Tu saldo de Stripe es de \(st.balance).")
                if let p = st.last.first {
                    out += t(" Dernier paiement : \(p.amount), il y a \(p.ago).", " Last payment: \(p.amount), \(p.ago) ago.",
                             " Último pago: \(p.amount), hace \(p.ago).")
                }
            }
            return out

        case .github:
            guard let g = s.github else {
                return t("Je n'ai pas encore les données GitHub.", "I don't have GitHub data yet.",
                         "Todavía no tengo los datos de GitHub.")
            }
            var parts: [String] = []
            if let stars = g.stars {
                let repos = g.repos.map { t(" sur \($0) repos", " across \($0) repos", " en \($0) repos") } ?? ""
                parts.append(t("Tu as \(stars) étoile\(stars > 1 ? "s" : "")\(repos).",
                               "You have \(stars) star\(stars == 1 ? "" : "s")\(repos).",
                               "Tienes \(stars) estrella\(stars == 1 ? "" : "s")\(repos)."))
            }
            if !g.myPRs.isEmpty {
                let red = g.myPRs.filter { $0.ci == "failure" }.count
                let plural = g.myPRs.count > 1 ? "s" : ""
                var p = t("\(g.myPRs.count) PR ouverte\(plural)", "\(g.myPRs.count) open PR\(plural)",
                          "\(g.myPRs.count) PR abierta\(plural)")
                if red > 0 { p += t(", dont \(red) avec la CI en échec", ", \(red) with failing CI", ", \(red) con la CI fallando") }
                parts.append(p + ".")
            }
            if g.toReview > 0 {
                parts.append(t("\(g.toReview) à relire.", "\(g.toReview) waiting for your review.", "\(g.toReview) por revisar."))
            }
            if let repo = g.failingRepos.first {
                parts.append(t("La CI de \(repo) est rouge.", "CI is red on \(repo).", "La CI de \(repo) está en rojo."))
            }
            return parts.isEmpty ? t("Rien de spécial sur GitHub.", "Nothing new on GitHub.", "Nada nuevo en GitHub.")
                                 : parts.joined(separator: " ")

        case .vercel:
            guard let d = s.deploys.first else {
                return t("Aucun déploiement Vercel récent.", "No recent Vercel deployment.",
                         "No hay despliegues recientes en Vercel.")
            }
            let ok = d.state == "READY"
            let state = ok ? t("est en ligne", "is live", "está en línea")
                : d.state == "ERROR" ? t("a échoué", "failed", "ha fallado")
                : d.state == "CANCELED" ? t("a été annulé", "was canceled", "se ha cancelado")
                : t("est en cours", "is in progress", "está en curso")
            var out = t("Le dernier déploiement de \(d.project) \(state), il y a \(d.ago).",
                        "The last \(d.project) deployment \(state), \(d.ago) ago.",
                        "El último despliegue de \(d.project) \(state), hace \(d.ago).")
            if !ok, let ready = s.deploys.dropFirst().first(where: { $0.state == "READY" }) {
                out += t(" Le précédent en ligne date de \(ready.ago).", " The previous live one is from \(ready.ago) ago.",
                         " El anterior en línea es de hace \(ready.ago).")
            }
            return out

        case .resend:
            if s.emails.isEmpty {
                return t("Aucun mail envoyé récemment avec Resend.", "No recent email sent with Resend.",
                         "No hay correos enviados recientemente con Resend.")
            }
            let e = s.emails[0]
            var out = s.emailsTotal.map { t("\($0) mails envoyés au total.", "\($0) emails sent in total.",
                                            "\($0) correos enviados en total.") } ?? ""
            out += t(" Le dernier, « \(e.subject) » à \(e.to) : \(e.state).", " Last one, “\(e.subject)” to \(e.to): \(e.state).",
                     " El último, «\(e.subject)» a \(e.to): \(e.state).")
            return out.trimmingCharacters(in: .whitespaces)

        case .n8n:
            guard let r = s.runs.first else {
                return t("Aucune exécution n8n récente.", "No recent n8n run.", "No hay ejecuciones recientes de n8n.")
            }
            let failed = s.runs.filter { !$0.ok }.count
            var out = t("Dernier workflow : \(r.workflow), \(r.ok ? "réussi" : "en échec"), il y a \(r.ago).",
                        "Last workflow: \(r.workflow), \(r.ok ? "succeeded" : "failed"), \(r.ago) ago.",
                        "Último workflow: \(r.workflow), \(r.ok ? "correcto" : "fallido"), hace \(r.ago).")
            if failed > 0 && r.ok {
                let plural = failed > 1 ? "s" : ""
                out += t(" \(failed) échec\(plural) récent\(plural).", " \(failed) recent failure\(plural).",
                         " \(failed) fallo\(plural) reciente\(plural).")
            }
            return out

        case .notion:
            guard let p = s.pages.first else {
                return t("Aucune page Notion récente.", "No recent Notion page.", "No hay páginas recientes en Notion.")
            }
            return t("Dernière page modifiée : \(p.title), il y a \(p.ago).", "Last edited page: \(p.title), \(p.ago) ago.",
                     "Última página editada: \(p.title), hace \(p.ago).")

        case .calcom:
            guard let b = s.bookings.first else {
                return t("Aucun rendez-vous à venir.", "No upcoming booking.", "No hay citas próximas.")
            }
            let who = b.with.map { t(" avec \($0)", " with \($0)", " con \($0)") } ?? ""
            var out = t("Prochain rendez-vous : \(b.title)\(who), \(b.when).", "Next booking: \(b.title)\(who), \(b.when).",
                        "Próxima cita: \(b.title)\(who), \(b.when).")
            if s.bookings.count > 1 {
                out += t(" \(s.bookings.count) au total.", " \(s.bookings.count) in total.", " \(s.bookings.count) en total.")
            }
            return out

        case .agents:
            if let tool = s.approvalPending {
                return t("Une demande d'autorisation attend ton clic : \(tool).", "A permission request is waiting for your click: \(tool).",
                         "Hay una solicitud de permiso esperando tu clic: \(tool).")
            }
            let busy = s.sessions.filter { $0.state != "idle" && $0.state != "sleeping" }
            guard !busy.isEmpty else {
                return t("Aucun agent ne travaille en ce moment.", "No agent is working right now.",
                         "Ningún agente está trabajando ahora mismo.")
            }
            // French and English keep their " : ", Spanish writes ":".
            let colon = lang == .es ? ":" : " :"
            return busy.prefix(3).map { a in
                let st = stateText(a.state, lang: lang)
                return a.detail.map { "\(a.name) \(st)\(colon) \($0)." } ?? "\(a.name) \(st)."
            }.joined(separator: " ")

        case .claudePlan, .codexPlan:
            let name = topic == .claudePlan ? "Claude" : "Codex"
            guard let p = s.plan, p.fiveHourPct != nil || p.sevenDayPct != nil else {
                return t("Je n'ai pas encore l'usage de ton plan \(name).", "I don't have your \(name) plan usage yet.",
                         "Todavía no tengo el uso de tu plan \(name).")
            }
            var parts: [String] = []
            if let h = p.fiveHourPct { parts.append(t("\(h) % sur 5 heures", "\(h)% of the 5-hour window", "\(h) % en 5 horas")) }
            if let w = p.sevenDayPct { parts.append(t("\(w) % sur la semaine", "\(w)% of the week", "\(w) % en la semana")) }
            var out = t("Plan \(name) : ", "\(name) plan: ", "Plan \(name): ") + parts.joined(separator: t(" et ", " and ", " y ")) + "."
            if let r = p.resetsIn { out += t(" Remise à zéro dans \(r).", " Resets in \(r).", " Se reinicia en \(r).") }
            return out

        case .music:
            guard let n = s.nowPlaying else {
                return t("Rien ne joue en ce moment.", "Nothing is playing right now.", "No suena nada ahora mismo.")
            }
            return n.artist.map { t("C'est \(n.title), de \($0).", "It's \(n.title) by \($0).", "Es \(n.title), de \($0).") } ?? n.title

        case .pills:
            let main = s.mainPill.map { t("Pilule principale : \($0).", "Main pill: \($0).", "Píldora principal: \($0).") } ?? ""
            let list = s.activePills.joined(separator: ", ")
            let others = s.activePills.isEmpty ? t(" Aucune autre pilule.", " No other pill.", " Ninguna otra píldora.")
                : t(" Actives : \(list).", " Active: \(list).", " Activas: \(list).")
            return (main + others).trimmingCharacters(in: .whitespaces)

        case .weatherToday, .weatherTomorrow:
            if s.weatherOff {
                return t("Active la météo dans les réglages de Coucou, section Voix.", "Turn on weather in Coucou's settings, Voice section.",
                         "Activa el tiempo en los ajustes de Coucou, sección Voz.")
            }
            if s.weatherNoCity {
                return t("Indique ta ville dans les réglages de Coucou, section Voix.", "Set your city in Coucou's settings, Voice section.",
                         "Indica tu ciudad en los ajustes de Coucou, sección Voz.")
            }
            guard let w = s.weather else {
                return t("Je n'arrive pas à avoir la météo pour l'instant.", "I can't get the weather right now.",
                         "Ahora mismo no consigo el tiempo.")
            }
            let sky = weatherText(w.code, lang: lang)
            var out: String
            if topic == .weatherTomorrow {
                out = t("Demain à \(w.city) : \(sky), de \(w.min) à \(w.max) degrés.", "Tomorrow in \(w.city): \(sky), \(w.min) to \(w.max) degrees.",
                        "Mañana en \(w.city): \(sky), de \(w.min) a \(w.max) grados.")
            } else if let now = w.nowTemp {
                out = t("À \(w.city), \(now) degrés, \(sky). Entre \(w.min) et \(w.max) aujourd'hui.",
                        "In \(w.city), \(now) degrees, \(sky). Between \(w.min) and \(w.max) today.",
                        "En \(w.city), \(now) grados, \(sky). Entre \(w.min) y \(w.max) hoy.")
            } else {
                out = t("Aujourd'hui à \(w.city) : \(sky), de \(w.min) à \(w.max) degrés.", "Today in \(w.city): \(sky), \(w.min) to \(w.max) degrees.",
                        "Hoy en \(w.city): \(sky), de \(w.min) a \(w.max) grados.")
            }
            if let rain = w.rainChance, rain >= 30 {
                out += t(" \(rain) % de risque de pluie.", " \(rain)% chance of rain.", " \(rain) % de probabilidad de lluvia.")
            }
            return out
        }
    }

    static func serviceName(_ topic: VoiceTopic) -> String {
        switch topic {
        case .stripe:     return "Stripe"
        case .github:     return "GitHub"
        case .vercel:     return "Vercel"
        case .resend:     return "Resend"
        case .n8n:        return "n8n"
        case .notion:     return "Notion"
        case .calcom:     return "Cal.com"
        case .claudePlan: return "Claude"
        case .codexPlan:  return "Codex"
        case .agents:     return "Claude Code"
        case .music:      return "Music"
        case .pills:      return "Coucou"
        case .weatherToday, .weatherTomorrow: return "Météo"
        }
    }

    static func stateText(_ state: String, lang: VoiceLang) -> String {
        switch state {
        case "working":   return lang.t("travaille", "is working", "está trabajando")
        case "thinking":  return lang.t("réfléchit", "is thinking", "está pensando")
        case "searching": return lang.t("cherche", "is searching", "está buscando")
        case "approval":  return lang.t("attend ton autorisation", "is waiting for your approval", "espera tu autorización")
        case "question":  return lang.t("te pose une question", "has a question for you", "tiene una pregunta para ti")
        case "error":     return lang.t("est en erreur", "hit an error", "ha dado un error")
        case "finished":  return lang.t("a terminé", "is done", "ha terminado")
        case "ratelimit": return lang.t("a atteint sa limite", "hit its rate limit", "ha llegado a su límite")
        default:          return lang.t("est actif", "is active", "está activo")
        }
    }

    /// WMO weather codes (Open-Meteo).
    static func weatherText(_ code: Int, lang: VoiceLang) -> String {
        switch code {
        case 0:            return lang.t("ciel dégagé", "clear sky", "cielo despejado")
        case 1, 2:         return lang.t("quelques nuages", "partly cloudy", "algunas nubes")
        case 3:            return lang.t("couvert", "overcast", "cubierto")
        case 45, 48:       return lang.t("brouillard", "fog", "niebla")
        case 51, 53, 55, 56, 57: return lang.t("bruine", "drizzle", "llovizna")
        case 61, 63, 66:   return lang.t("pluie", "rain", "lluvia")
        case 65, 67:       return lang.t("forte pluie", "heavy rain", "lluvia fuerte")
        case 71, 73, 75, 77: return lang.t("neige", "snow", "nieve")
        case 80, 81:       return lang.t("averses", "showers", "chubascos")
        case 82:           return lang.t("fortes averses", "heavy showers", "chubascos fuertes")
        case 85, 86:       return lang.t("averses de neige", "snow showers", "chubascos de nieve")
        case 95, 96, 99:   return lang.t("orages", "thunderstorms", "tormentas")
        default:           return lang.t("temps variable", "mixed weather", "tiempo variable")
        }
    }
}
#endif
