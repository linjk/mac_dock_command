import Foundation

struct CommandConfig: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var command: String
    var cwd: String?
    var env: [String: String]

    init(id: UUID, name: String, command: String, cwd: String? = nil, env: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.command = command
        self.cwd = cwd
        self.env = env
    }

    enum CodingKeys: String, CodingKey {
        case id, name, command, cwd, env
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        command = try c.decode(String.self, forKey: .command)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(command, forKey: .command)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        if !env.isEmpty { try c.encode(env, forKey: .env) }
    }
}
