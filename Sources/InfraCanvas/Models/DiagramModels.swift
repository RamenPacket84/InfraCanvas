import Foundation
import SwiftUI

struct Board: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var nodes: [DiagramNode]
    var edges: [DiagramEdge]
    var groups: [DiagramGroup] = []
    var backgroundStyle: BoardBackgroundStyle = .grid

    init(
        id: UUID = UUID(),
        name: String,
        nodes: [DiagramNode],
        edges: [DiagramEdge],
        groups: [DiagramGroup] = [],
        backgroundStyle: BoardBackgroundStyle = .grid
    ) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.edges = edges
        self.groups = groups
        self.backgroundStyle = backgroundStyle
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nodes
        case edges
        case groups
        case backgroundStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        nodes = try container.decode([DiagramNode].self, forKey: .nodes)
        edges = try container.decode([DiagramEdge].self, forKey: .edges)
        groups = try container.decodeIfPresent([DiagramGroup].self, forKey: .groups) ?? []
        backgroundStyle = try container.decodeIfPresent(BoardBackgroundStyle.self, forKey: .backgroundStyle) ?? .grid
    }

    var connectorEndpointNodeIDs: Set<DiagramNode.ID> {
        Set(edges.flatMap { [$0.sourceNodeID, $0.targetNodeID] })
    }
}

enum BoardBackgroundStyle: String, CaseIterable, Identifiable, Codable {
    case grid
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid Background"
        case .solid: "Solid Background"
        }
    }

    var symbolName: String {
        switch self {
        case .grid: "square.grid.3x3"
        case .solid: "square"
        }
    }
}

struct DiagramNode: Identifiable, Equatable, Codable {
    var id = UUID()
    var title: String
    var subtitle: String
    var notes: String
    var symbolName: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var tint: NodeTint
    var category: ComponentCategory

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        notes: String = "",
        symbolName: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        tint: NodeTint,
        category: ComponentCategory
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.notes = notes
        self.symbolName = symbolName
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.tint = tint
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case notes
        case symbolName
        case x
        case y
        case width
        case height
        case tint
        case category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        symbolName = try container.decode(String.self, forKey: .symbolName)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        tint = try container.decode(NodeTint.self, forKey: .tint)
        category = try container.decode(ComponentCategory.self, forKey: .category)
    }

    var position: CGPoint {
        get { CGPoint(x: x, y: y) }
        set {
            x = newValue.x
            y = newValue.y
        }
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

struct DiagramEdge: Identifiable, Equatable, Codable {
    var id = UUID()
    var sourceNodeID: DiagramNode.ID
    var targetNodeID: DiagramNode.ID
    var label: String
    var showsLabel = true
    var hasArrow = true
    var style: ConnectorStyle = .straight
    var kind: ConnectorKind = .generic

    init(
        id: UUID = UUID(),
        sourceNodeID: DiagramNode.ID,
        targetNodeID: DiagramNode.ID,
        label: String,
        showsLabel: Bool = true,
        hasArrow: Bool = true,
        style: ConnectorStyle = .straight,
        kind: ConnectorKind = .generic
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.label = label
        self.showsLabel = showsLabel
        self.hasArrow = hasArrow
        self.style = style
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceNodeID
        case targetNodeID
        case label
        case showsLabel
        case hasArrow
        case style
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourceNodeID = try container.decode(DiagramNode.ID.self, forKey: .sourceNodeID)
        targetNodeID = try container.decode(DiagramNode.ID.self, forKey: .targetNodeID)
        label = try container.decode(String.self, forKey: .label)
        showsLabel = try container.decodeIfPresent(Bool.self, forKey: .showsLabel) ?? true
        hasArrow = try container.decodeIfPresent(Bool.self, forKey: .hasArrow) ?? true
        style = try container.decodeIfPresent(ConnectorStyle.self, forKey: .style) ?? .straight
        kind = try container.decodeIfPresent(ConnectorKind.self, forKey: .kind) ?? .generic
    }
}

enum ConnectorStyle: String, CaseIterable, Identifiable, Codable {
    case straight
    case orthogonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight: "Straight"
        case .orthogonal: "Elbow"
        }
    }

    var symbolName: String {
        switch self {
        case .straight: "line.diagonal"
        case .orthogonal: "arrow.triangle.branch"
        }
    }
}

enum ConnectorKind: String, CaseIterable, Identifiable, Codable {
    case generic
    case ethernet
    case wifi
    case fiber
    case vpn
    case power
    case dependency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generic: "Generic"
        case .ethernet: "Ethernet"
        case .wifi: "Wi-Fi"
        case .fiber: "Fiber"
        case .vpn: "VPN"
        case .power: "Power / PoE"
        case .dependency: "Dependency"
        }
    }

    var symbolName: String {
        switch self {
        case .generic: "link"
        case .ethernet: "switch.2"
        case .wifi: "wifi"
        case .fiber: "point.3.connected.trianglepath.dotted"
        case .vpn: "lock.rectangle"
        case .power: "bolt"
        case .dependency: "arrow.triangle.branch"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .ethernet, .fiber, .power: 2.4
        case .dependency: 1.7
        case .generic, .wifi, .vpn: 2
        }
    }

    func dashPattern(scale: CGFloat = 1) -> [CGFloat] {
        let pattern: [CGFloat]
        switch self {
        case .generic, .ethernet, .fiber, .power:
            pattern = []
        case .wifi:
            pattern = [5, 5]
        case .vpn:
            pattern = [9, 5]
        case .dependency:
            pattern = [3, 5]
        }

        return pattern.map { $0 * scale }
    }
}

struct DiagramGroup: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var nodeIDs: Set<DiagramNode.ID>
}

enum CanvasTool: String, CaseIterable, Identifiable {
    case select
    case pan
    case connect

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .pan: "hand.draw"
        case .connect: "point.3.connected.trianglepath.dotted"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .pan: "Pan"
        case .connect: "Connect"
        }
    }
}

enum ComponentCategory: String, CaseIterable, Identifiable, Codable {
    case general = "General"
    case people = "People"
    case device = "Devices"
    case network = "Network"
    case identity = "Identity"
    case cloud = "Cloud"
    case service = "Services"
    case data = "Data"
    case process = "Process"
    case security = "Security"

    var id: String { rawValue }
}

enum NodeTint: String, CaseIterable, Identifiable, Codable {
    case blue
    case green
    case orange
    case purple
    case red
    case gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        case .red: .red
        case .gray: .gray
        }
    }
}

struct ComponentTemplate: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var subtitle: String
    var symbolName: String
    var tint: NodeTint
    var category: ComponentCategory

    var searchText: String {
        "\(title) \(subtitle) \(symbolName) \(category.rawValue)".lowercased()
    }

    static let defaultTemplate = ComponentTemplate(
        title: "Component",
        subtitle: "New idea",
        symbolName: "square.stack.3d.up",
        tint: .blue,
        category: .general
    )

    static let library: [ComponentTemplate] = [
        ComponentTemplate(title: "Component", subtitle: "Generic building block", symbolName: "square.stack.3d.up", tint: .blue, category: .general),
        ComponentTemplate(title: "Note", subtitle: "Context or reminder", symbolName: "note.text", tint: .gray, category: .general),
        ComponentTemplate(title: "Question", subtitle: "Unknown or open item", symbolName: "questionmark.bubble", tint: .orange, category: .general),
        ComponentTemplate(title: "Dependency", subtitle: "Requirement or prerequisite", symbolName: "link", tint: .orange, category: .general),
        ComponentTemplate(title: "Milestone", subtitle: "Target or checkpoint", symbolName: "flag", tint: .green, category: .general),
        ComponentTemplate(title: "Risk", subtitle: "Concern or blocker", symbolName: "exclamationmark.triangle", tint: .red, category: .general),
        ComponentTemplate(title: "Boundary", subtitle: "Scope or ownership edge", symbolName: "rectangle.dashed", tint: .gray, category: .general),
        ComponentTemplate(title: "Requirement", subtitle: "Need or expected capability", symbolName: "checklist", tint: .green, category: .general),
        ComponentTemplate(title: "Constraint", subtitle: "Limit, rule, or condition", symbolName: "exclamationmark.lock", tint: .red, category: .general),
        ComponentTemplate(title: "Assumption", subtitle: "Belief to validate", symbolName: "lightbulb", tint: .orange, category: .general),
        ComponentTemplate(title: "Outcome", subtitle: "Desired result", symbolName: "target", tint: .green, category: .general),
        ComponentTemplate(title: "Timeline", subtitle: "Date or sequence", symbolName: "clock", tint: .gray, category: .general),
        ComponentTemplate(title: "Environment", subtitle: "Dev, test, stage, or prod", symbolName: "square.3.layers.3d", tint: .blue, category: .general),
        ComponentTemplate(title: "Decision Record", subtitle: "Choice and rationale", symbolName: "doc.text.magnifyingglass", tint: .gray, category: .general),
        ComponentTemplate(title: "Whiteboard", subtitle: "Sketch or rough model", symbolName: "rectangle.and.pencil.and.ellipsis", tint: .gray, category: .general),
        ComponentTemplate(title: "Idea", subtitle: "Concept or brainstorm item", symbolName: "lightbulb.max", tint: .orange, category: .general),
        ComponentTemplate(title: "Reference", subtitle: "Supporting material", symbolName: "bookmark", tint: .gray, category: .general),
        ComponentTemplate(title: "Attachment", subtitle: "Linked file or evidence", symbolName: "paperclip", tint: .gray, category: .general),
        ComponentTemplate(title: "Checklist", subtitle: "Tasks or verification list", symbolName: "checklist.checked", tint: .green, category: .general),
        ComponentTemplate(title: "Scope Item", subtitle: "Included work or area", symbolName: "scope", tint: .blue, category: .general),
        ComponentTemplate(title: "Out of Scope", subtitle: "Excluded work or area", symbolName: "nosign", tint: .red, category: .general),
        ComponentTemplate(title: "Pinned Item", subtitle: "Important or fixed item", symbolName: "pin", tint: .orange, category: .general),

        ComponentTemplate(title: "Person", subtitle: "User, customer, stakeholder", symbolName: "person.crop.circle", tint: .purple, category: .people),
        ComponentTemplate(title: "Team", subtitle: "Group or owner", symbolName: "person.3", tint: .purple, category: .people),
        ComponentTemplate(title: "Administrator", subtitle: "Privileged operator", symbolName: "person.badge.key", tint: .purple, category: .people),
        ComponentTemplate(title: "Vendor", subtitle: "External provider", symbolName: "building.2", tint: .purple, category: .people),
        ComponentTemplate(title: "Support", subtitle: "Help desk or operations", symbolName: "headphones", tint: .purple, category: .people),
        ComponentTemplate(title: "Approver", subtitle: "Reviewer or decision maker", symbolName: "person.crop.circle.badge.checkmark", tint: .purple, category: .people),
        ComponentTemplate(title: "Customer", subtitle: "External user or buyer", symbolName: "person.crop.circle.badge.questionmark", tint: .purple, category: .people),
        ComponentTemplate(title: "Sponsor", subtitle: "Business owner or funder", symbolName: "person.crop.circle.badge.checkmark", tint: .purple, category: .people),
        ComponentTemplate(title: "Product Owner", subtitle: "Prioritization owner", symbolName: "person.crop.rectangle", tint: .purple, category: .people),
        ComponentTemplate(title: "Engineer", subtitle: "Builder or implementer", symbolName: "hammer", tint: .purple, category: .people),
        ComponentTemplate(title: "Operator", subtitle: "Runs the solution", symbolName: "wrench.and.screwdriver", tint: .purple, category: .people),
        ComponentTemplate(title: "Auditor", subtitle: "Reviewer or compliance role", symbolName: "doc.text.magnifyingglass", tint: .purple, category: .people),
        ComponentTemplate(title: "Guest", subtitle: "Temporary or external user", symbolName: "person.crop.circle.badge.plus", tint: .purple, category: .people),
        ComponentTemplate(title: "Manager", subtitle: "People or delivery lead", symbolName: "person.2.badge.gearshape", tint: .purple, category: .people),
        ComponentTemplate(title: "Trainer", subtitle: "Enablement or education", symbolName: "graduationcap", tint: .purple, category: .people),
        ComponentTemplate(title: "Analyst", subtitle: "Research or reporting role", symbolName: "chart.bar.xaxis", tint: .purple, category: .people),
        ComponentTemplate(title: "Partner", subtitle: "Joint delivery group", symbolName: "person.2.wave.2", tint: .purple, category: .people),
        ComponentTemplate(title: "Executive", subtitle: "Leadership stakeholder", symbolName: "briefcase", tint: .purple, category: .people),
        ComponentTemplate(title: "Requester", subtitle: "Asks for work or access", symbolName: "person.badge.plus", tint: .purple, category: .people),
        ComponentTemplate(title: "Resolver", subtitle: "Fixes issue or request", symbolName: "person.badge.clock", tint: .purple, category: .people),

        ComponentTemplate(title: "Mac", subtitle: "macOS computer", symbolName: "macbook", tint: .gray, category: .device),
        ComponentTemplate(title: "Workstation", subtitle: "Desktop or laptop", symbolName: "desktopcomputer", tint: .gray, category: .device),
        ComponentTemplate(title: "Windows PC", subtitle: "Managed Windows device", symbolName: "display", tint: .gray, category: .device),
        ComponentTemplate(title: "Mobile Device", subtitle: "Phone or tablet", symbolName: "iphone", tint: .gray, category: .device),
        ComponentTemplate(title: "Tablet", subtitle: "iPad or shared tablet", symbolName: "ipad", tint: .gray, category: .device),
        ComponentTemplate(title: "Server", subtitle: "Compute host", symbolName: "server.rack", tint: .gray, category: .device),
        ComponentTemplate(title: "Printer", subtitle: "Print or scan endpoint", symbolName: "printer", tint: .gray, category: .device),
        ComponentTemplate(title: "Kiosk", subtitle: "Shared purpose-built endpoint", symbolName: "rectangle.on.rectangle", tint: .gray, category: .device),
        ComponentTemplate(title: "Sensor", subtitle: "IoT or telemetry device", symbolName: "sensor.tag.radiowaves.forward", tint: .gray, category: .device),
        ComponentTemplate(title: "Virtual Machine", subtitle: "Hosted compute instance", symbolName: "cpu", tint: .gray, category: .device),
        ComponentTemplate(title: "Container Host", subtitle: "Runtime node", symbolName: "shippingbox", tint: .gray, category: .device),
        ComponentTemplate(title: "Appliance", subtitle: "Dedicated hardware service", symbolName: "server.rack", tint: .gray, category: .device),
        ComponentTemplate(title: "Gateway", subtitle: "Edge or bridge device", symbolName: "arrow.left.arrow.right.square", tint: .gray, category: .device),
        ComponentTemplate(title: "Shared Device", subtitle: "Multi-user endpoint", symbolName: "person.2.crop.square.stack", tint: .gray, category: .device),
        ComponentTemplate(title: "Peripheral", subtitle: "Attached device or accessory", symbolName: "keyboard", tint: .gray, category: .device),
        ComponentTemplate(title: "Laptop", subtitle: "Portable computer", symbolName: "laptopcomputer", tint: .gray, category: .device),
        ComponentTemplate(title: "Display", subtitle: "Monitor or screen", symbolName: "display.2", tint: .gray, category: .device),
        ComponentTemplate(title: "Apple Watch", subtitle: "Wearable endpoint", symbolName: "applewatch", tint: .gray, category: .device),
        ComponentTemplate(title: "Scanner", subtitle: "Capture or intake device", symbolName: "scanner", tint: .gray, category: .device),
        ComponentTemplate(title: "External Drive", subtitle: "Attached storage", symbolName: "externaldrive", tint: .gray, category: .device),
        ComponentTemplate(title: "Battery Device", subtitle: "Mobile or powered endpoint", symbolName: "battery.100", tint: .gray, category: .device),
        ComponentTemplate(title: "Power Adapter", subtitle: "Power source or charger", symbolName: "powerplug", tint: .gray, category: .device),
        ComponentTemplate(title: "Mouse", subtitle: "Pointing device", symbolName: "computermouse", tint: .gray, category: .device),

        ComponentTemplate(title: "Network", subtitle: "Segment or route", symbolName: "network", tint: .green, category: .network),
        ComponentTemplate(title: "LAN", subtitle: "Local area network", symbolName: "point.3.connected.trianglepath.dotted", tint: .green, category: .network),
        ComponentTemplate(title: "Wi-Fi", subtitle: "Wireless access", symbolName: "wifi", tint: .green, category: .network),
        ComponentTemplate(title: "Internet", subtitle: "External network path", symbolName: "globe", tint: .blue, category: .network),
        ComponentTemplate(title: "VPN", subtitle: "Private tunnel", symbolName: "lock.rectangle", tint: .green, category: .network),
        ComponentTemplate(title: "Firewall", subtitle: "Network security boundary", symbolName: "shield.lefthalf.filled", tint: .red, category: .network),
        ComponentTemplate(title: "Router", subtitle: "Traffic routing point", symbolName: "arrow.triangle.swap", tint: .green, category: .network),
        ComponentTemplate(title: "Switch", subtitle: "Layer 2 connection point", symbolName: "switch.2", tint: .green, category: .network),
        ComponentTemplate(title: "Subnet", subtitle: "Address or trust zone", symbolName: "square.grid.3x3", tint: .green, category: .network),
        ComponentTemplate(title: "Load Balancer", subtitle: "Traffic distribution", symbolName: "arrow.triangle.branch", tint: .green, category: .network),
        ComponentTemplate(title: "DNS", subtitle: "Name resolution", symbolName: "textformat.abc", tint: .green, category: .network),
        ComponentTemplate(title: "Proxy", subtitle: "Mediated network path", symbolName: "arrow.left.arrow.right.circle", tint: .green, category: .network),
        ComponentTemplate(title: "CDN", subtitle: "Content delivery edge", symbolName: "globe.americas", tint: .green, category: .network),
        ComponentTemplate(title: "NAT", subtitle: "Address translation", symbolName: "arrow.triangle.2.circlepath", tint: .green, category: .network),
        ComponentTemplate(title: "VLAN", subtitle: "Logical network boundary", symbolName: "rectangle.3.group", tint: .green, category: .network),
        ComponentTemplate(title: "Packet Flow", subtitle: "Traffic path or rule", symbolName: "arrow.right", tint: .green, category: .network),
        ComponentTemplate(title: "Wireless AP", subtitle: "Access point", symbolName: "antenna.radiowaves.left.and.right", tint: .green, category: .network),
        ComponentTemplate(title: "Cellular", subtitle: "Mobile network path", symbolName: "antenna.radiowaves.left.and.right.circle", tint: .green, category: .network),
        ComponentTemplate(title: "Secure Tunnel", subtitle: "Encrypted network path", symbolName: "lock.rectangle.stack", tint: .green, category: .network),
        ComponentTemplate(title: "Port", subtitle: "Service port or listener", symbolName: "circle.grid.cross", tint: .green, category: .network),
        ComponentTemplate(title: "Peering", subtitle: "Network-to-network link", symbolName: "arrow.left.and.right", tint: .green, category: .network),
        ComponentTemplate(title: "Transit", subtitle: "Hub routing path", symbolName: "arrow.triangle.merge", tint: .green, category: .network),
        ComponentTemplate(title: "Ingress", subtitle: "Inbound traffic entry", symbolName: "arrow.down.to.line", tint: .green, category: .network),
        ComponentTemplate(title: "Egress", subtitle: "Outbound traffic exit", symbolName: "arrow.up.to.line", tint: .green, category: .network),

        ComponentTemplate(title: "User Account", subtitle: "Identity record", symbolName: "person.text.rectangle", tint: .purple, category: .identity),
        ComponentTemplate(title: "Group", subtitle: "Access collection", symbolName: "person.2", tint: .purple, category: .identity),
        ComponentTemplate(title: "Role", subtitle: "Permission set", symbolName: "person.badge.shield.checkmark", tint: .purple, category: .identity),
        ComponentTemplate(title: "Certificate", subtitle: "Trust or device identity", symbolName: "checkmark.seal", tint: .red, category: .identity),
        ComponentTemplate(title: "Token", subtitle: "Session or API credential", symbolName: "ticket", tint: .red, category: .identity),
        ComponentTemplate(title: "MFA", subtitle: "Multi-factor authentication", symbolName: "lock.shield", tint: .red, category: .identity),
        ComponentTemplate(title: "SSO", subtitle: "Single sign-on flow", symbolName: "person.crop.circle.badge.checkmark", tint: .purple, category: .identity),
        ComponentTemplate(title: "Directory", subtitle: "Identity source", symbolName: "person.3.sequence", tint: .purple, category: .identity),
        ComponentTemplate(title: "IdP", subtitle: "Identity provider", symbolName: "person.badge.shield.checkmark", tint: .purple, category: .identity),
        ComponentTemplate(title: "Service Account", subtitle: "Non-human identity", symbolName: "key", tint: .purple, category: .identity),
        ComponentTemplate(title: "Access Review", subtitle: "Entitlement check", symbolName: "person.crop.circle.badge.exclamationmark", tint: .purple, category: .identity),
        ComponentTemplate(title: "Conditional Access", subtitle: "Context-based policy", symbolName: "lock.badge.clock", tint: .red, category: .identity),
        ComponentTemplate(title: "Provisioning", subtitle: "Create or sync identity", symbolName: "person.crop.circle.badge.plus", tint: .purple, category: .identity),
        ComponentTemplate(title: "Deprovisioning", subtitle: "Remove or disable access", symbolName: "person.crop.circle.badge.minus", tint: .red, category: .identity),
        ComponentTemplate(title: "Passkey", subtitle: "Passwordless credential", symbolName: "person.badge.key", tint: .red, category: .identity),
        ComponentTemplate(title: "Password", subtitle: "User secret", symbolName: "lock.rectangle", tint: .red, category: .identity),
        ComponentTemplate(title: "Smart Card", subtitle: "Hardware credential", symbolName: "creditcard.and.123", tint: .red, category: .identity),
        ComponentTemplate(title: "Device Identity", subtitle: "Trusted endpoint identity", symbolName: "laptopcomputer.and.iphone", tint: .purple, category: .identity),
        ComponentTemplate(title: "Entitlement", subtitle: "Granted access", symbolName: "checkmark.circle.badge.questionmark", tint: .purple, category: .identity),
        ComponentTemplate(title: "Access Package", subtitle: "Bundled entitlements", symbolName: "shippingbox.and.arrow.backward", tint: .purple, category: .identity),
        ComponentTemplate(title: "Federation", subtitle: "External trust relationship", symbolName: "person.line.dotted.person", tint: .purple, category: .identity),
        ComponentTemplate(title: "Break Glass", subtitle: "Emergency access path", symbolName: "exclamationmark.triangle.fill", tint: .red, category: .identity),

        ComponentTemplate(title: "Cloud Platform", subtitle: "Hosted environment", symbolName: "cloud", tint: .blue, category: .cloud),
        ComponentTemplate(title: "SaaS", subtitle: "External application service", symbolName: "globe.badge.chevron.backward", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Tenant", subtitle: "Cloud organization boundary", symbolName: "building.columns", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Automation", subtitle: "Scripted or scheduled action", symbolName: "gearshape.2", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Function", subtitle: "Event-driven compute", symbolName: "bolt", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Container", subtitle: "Packaged workload", symbolName: "shippingbox", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Integration", subtitle: "System-to-system link", symbolName: "arrow.left.arrow.right", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Region", subtitle: "Cloud geography", symbolName: "map", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Subscription", subtitle: "Billing or resource scope", symbolName: "creditcard", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Resource Group", subtitle: "Managed resource set", symbolName: "square.stack.3d.up", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Secret Vault", subtitle: "Cloud secret storage", symbolName: "lock.square.stack", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Scheduler", subtitle: "Time-triggered cloud work", symbolName: "calendar.badge.clock", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Event Bus", subtitle: "Cloud event routing", symbolName: "bolt.horizontal.circle", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Upload", subtitle: "Send data to cloud", symbolName: "icloud.and.arrow.up", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Download", subtitle: "Receive data from cloud", symbolName: "icloud.and.arrow.down", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Sync", subtitle: "Cloud synchronization", symbolName: "arrow.triangle.2.circlepath", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Firewall", subtitle: "Cloud boundary control", symbolName: "firewall", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Database", subtitle: "Hosted data service", symbolName: "cylinder.split.1x2", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Storage", subtitle: "Hosted file or object store", symbolName: "externaldrive.badge.icloud", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Cost", subtitle: "Spend or billing signal", symbolName: "dollarsign.circle", tint: .blue, category: .cloud),
        ComponentTemplate(title: "Cloud Policy", subtitle: "Cloud guardrail or rule", symbolName: "checkmark.shield", tint: .blue, category: .cloud),

        ComponentTemplate(title: "Application", subtitle: "App or product surface", symbolName: "app.connected.to.app.below.fill", tint: .blue, category: .service),
        ComponentTemplate(title: "Cloud Service", subtitle: "Hosted platform or SaaS", symbolName: "cloud", tint: .blue, category: .service),
        ComponentTemplate(title: "API", subtitle: "Interface or integration", symbolName: "curlybraces.square", tint: .blue, category: .service),
        ComponentTemplate(title: "Web App", subtitle: "Browser-based experience", symbolName: "safari", tint: .blue, category: .service),
        ComponentTemplate(title: "Mobile App", subtitle: "iOS or Android app", symbolName: "apps.iphone", tint: .blue, category: .service),
        ComponentTemplate(title: "Agent", subtitle: "Local helper or daemon", symbolName: "gearshape", tint: .blue, category: .service),
        ComponentTemplate(title: "Portal", subtitle: "Admin or user interface", symbolName: "rectangle.grid.2x2", tint: .blue, category: .service),
        ComponentTemplate(title: "Notification", subtitle: "Alert or message", symbolName: "bell", tint: .orange, category: .service),
        ComponentTemplate(title: "Workflow Engine", subtitle: "Coordinates tasks", symbolName: "flowchart", tint: .blue, category: .service),
        ComponentTemplate(title: "Job Runner", subtitle: "Background work", symbolName: "play.rectangle", tint: .blue, category: .service),
        ComponentTemplate(title: "Email Service", subtitle: "Messaging channel", symbolName: "envelope", tint: .blue, category: .service),
        ComponentTemplate(title: "Webhook", subtitle: "HTTP event callback", symbolName: "arrowshape.turn.up.forward", tint: .blue, category: .service),
        ComponentTemplate(title: "Rules Engine", subtitle: "Business logic", symbolName: "slider.horizontal.3", tint: .blue, category: .service),
        ComponentTemplate(title: "Monitoring", subtitle: "Health and availability", symbolName: "waveform.path.ecg", tint: .orange, category: .service),
        ComponentTemplate(title: "Dashboard", subtitle: "Operational overview", symbolName: "chart.line.uptrend.xyaxis", tint: .blue, category: .service),
        ComponentTemplate(title: "Search Service", subtitle: "Lookup or indexing", symbolName: "magnifyingglass", tint: .blue, category: .service),
        ComponentTemplate(title: "Chat Service", subtitle: "Conversation channel", symbolName: "bubble.left.and.bubble.right", tint: .blue, category: .service),
        ComponentTemplate(title: "Ticket System", subtitle: "Request or issue tracking", symbolName: "ticket", tint: .blue, category: .service),
        ComponentTemplate(title: "Package", subtitle: "Installable app or bundle", symbolName: "shippingbox", tint: .blue, category: .service),
        ComponentTemplate(title: "Update Service", subtitle: "Patch or version delivery", symbolName: "arrow.triangle.2.circlepath", tint: .blue, category: .service),
        ComponentTemplate(title: "Health Check", subtitle: "Availability probe", symbolName: "heart.text.square", tint: .orange, category: .service),
        ComponentTemplate(title: "Feature Flag", subtitle: "Controlled rollout", symbolName: "flag.2.crossed", tint: .blue, category: .service),

        ComponentTemplate(title: "Database", subtitle: "Structured data store", symbolName: "cylinder.split.1x2", tint: .orange, category: .data),
        ComponentTemplate(title: "File Store", subtitle: "Documents or object storage", symbolName: "folder", tint: .orange, category: .data),
        ComponentTemplate(title: "Message Queue", subtitle: "Async work or events", symbolName: "tray.2", tint: .orange, category: .data),
        ComponentTemplate(title: "Object Storage", subtitle: "Blob or bucket storage", symbolName: "externaldrive", tint: .orange, category: .data),
        ComponentTemplate(title: "Cache", subtitle: "Temporary fast storage", symbolName: "memorychip", tint: .orange, category: .data),
        ComponentTemplate(title: "Log Stream", subtitle: "Events and diagnostics", symbolName: "list.bullet.rectangle", tint: .orange, category: .data),
        ComponentTemplate(title: "Report", subtitle: "Output or dashboard", symbolName: "chart.bar.doc.horizontal", tint: .orange, category: .data),
        ComponentTemplate(title: "Backup", subtitle: "Recovery copy", symbolName: "clock.arrow.circlepath", tint: .orange, category: .data),
        ComponentTemplate(title: "Data Warehouse", subtitle: "Analytics store", symbolName: "cylinder.split.1x2", tint: .orange, category: .data),
        ComponentTemplate(title: "Data Lake", subtitle: "Raw or semi-structured data", symbolName: "externaldrive.badge.icloud", tint: .orange, category: .data),
        ComponentTemplate(title: "Schema", subtitle: "Data shape or contract", symbolName: "tablecells", tint: .orange, category: .data),
        ComponentTemplate(title: "ETL", subtitle: "Extract, transform, load", symbolName: "arrow.triangle.pull", tint: .orange, category: .data),
        ComponentTemplate(title: "Metrics", subtitle: "Measures and KPIs", symbolName: "chart.xyaxis.line", tint: .orange, category: .data),
        ComponentTemplate(title: "Archive", subtitle: "Long-term retention", symbolName: "archivebox", tint: .orange, category: .data),
        ComponentTemplate(title: "Data Pipeline", subtitle: "Data movement path", symbolName: "point.3.filled.connected.trianglepath.dotted", tint: .orange, category: .data),
        ComponentTemplate(title: "Data Source", subtitle: "Origin system or feed", symbolName: "tray.and.arrow.down", tint: .orange, category: .data),
        ComponentTemplate(title: "Data Sink", subtitle: "Destination system", symbolName: "tray.and.arrow.up", tint: .orange, category: .data),
        ComponentTemplate(title: "Dataset", subtitle: "Managed collection", symbolName: "tablecells.badge.ellipsis", tint: .orange, category: .data),
        ComponentTemplate(title: "Data Quality", subtitle: "Validation or completeness", symbolName: "checkmark.seal", tint: .orange, category: .data),
        ComponentTemplate(title: "Data Masking", subtitle: "Redaction or obfuscation", symbolName: "eye.slash", tint: .orange, category: .data),
        ComponentTemplate(title: "Snapshot", subtitle: "Point-in-time copy", symbolName: "camera", tint: .orange, category: .data),
        ComponentTemplate(title: "Retention", subtitle: "Lifecycle or expiry rule", symbolName: "calendar.badge.clock", tint: .orange, category: .data),

        ComponentTemplate(title: "Process Step", subtitle: "Action or workflow stage", symbolName: "arrow.triangle.branch", tint: .green, category: .process),
        ComponentTemplate(title: "Decision", subtitle: "Branch or condition", symbolName: "diamond", tint: .green, category: .process),
        ComponentTemplate(title: "Document", subtitle: "Requirement or artifact", symbolName: "doc.text", tint: .green, category: .process),
        ComponentTemplate(title: "Approval", subtitle: "Review or authorization", symbolName: "checkmark.seal", tint: .green, category: .process),
        ComponentTemplate(title: "Handoff", subtitle: "Ownership transfer", symbolName: "arrowshape.turn.up.right", tint: .green, category: .process),
        ComponentTemplate(title: "Schedule", subtitle: "Time-based activity", symbolName: "calendar", tint: .green, category: .process),
        ComponentTemplate(title: "Manual Task", subtitle: "Human action", symbolName: "hand.raised", tint: .green, category: .process),
        ComponentTemplate(title: "Automation Step", subtitle: "Automated workflow stage", symbolName: "play.rectangle", tint: .green, category: .process),
        ComponentTemplate(title: "Start", subtitle: "Workflow entry point", symbolName: "play.circle", tint: .green, category: .process),
        ComponentTemplate(title: "End", subtitle: "Workflow completion", symbolName: "stop.circle", tint: .green, category: .process),
        ComponentTemplate(title: "Exception", subtitle: "Failure or alternate path", symbolName: "exclamationmark.arrow.triangle.2.circlepath", tint: .red, category: .process),
        ComponentTemplate(title: "Escalation", subtitle: "Raise priority or owner", symbolName: "arrow.up.circle", tint: .orange, category: .process),
        ComponentTemplate(title: "SLA", subtitle: "Service level target", symbolName: "timer", tint: .green, category: .process),
        ComponentTemplate(title: "Runbook", subtitle: "Operational procedure", symbolName: "book", tint: .green, category: .process),
        ComponentTemplate(title: "Queue", subtitle: "Waiting work", symbolName: "line.3.horizontal.decrease.circle", tint: .green, category: .process),
        ComponentTemplate(title: "Intake", subtitle: "Request entry point", symbolName: "tray.and.arrow.down", tint: .green, category: .process),
        ComponentTemplate(title: "Triage", subtitle: "Sort and prioritize", symbolName: "list.bullet.indent", tint: .green, category: .process),
        ComponentTemplate(title: "Review", subtitle: "Check or inspect", symbolName: "magnifyingglass.circle", tint: .green, category: .process),
        ComponentTemplate(title: "Rollback", subtitle: "Revert to previous state", symbolName: "arrow.uturn.backward.circle", tint: .orange, category: .process),
        ComponentTemplate(title: "Retry", subtitle: "Repeat failed action", symbolName: "arrow.clockwise.circle", tint: .orange, category: .process),
        ComponentTemplate(title: "Wait State", subtitle: "Pending time or dependency", symbolName: "hourglass", tint: .green, category: .process),
        ComponentTemplate(title: "Notification Step", subtitle: "Tell users or systems", symbolName: "bell.badge", tint: .green, category: .process),

        ComponentTemplate(title: "Security Control", subtitle: "Guardrail or protection", symbolName: "lock.shield", tint: .red, category: .security),
        ComponentTemplate(title: "Credential", subtitle: "Secret, token, or key", symbolName: "key", tint: .red, category: .security),
        ComponentTemplate(title: "Policy", subtitle: "Rule or configuration", symbolName: "doc.badge.gearshape", tint: .red, category: .security),
        ComponentTemplate(title: "Secret", subtitle: "Password or private value", symbolName: "lock", tint: .red, category: .security),
        ComponentTemplate(title: "Audit", subtitle: "Review or evidence", symbolName: "checklist", tint: .red, category: .security),
        ComponentTemplate(title: "Alert", subtitle: "Signal or incident", symbolName: "exclamationmark.octagon", tint: .red, category: .security),
        ComponentTemplate(title: "Compliance", subtitle: "Standard or requirement", symbolName: "checkmark.shield", tint: .red, category: .security),
        ComponentTemplate(title: "Encryption", subtitle: "Protected data path", symbolName: "lock.rotation", tint: .red, category: .security),
        ComponentTemplate(title: "Threat", subtitle: "Abuse case or attacker path", symbolName: "exclamationmark.shield", tint: .red, category: .security),
        ComponentTemplate(title: "Vulnerability", subtitle: "Weakness or exposure", symbolName: "ant", tint: .red, category: .security),
        ComponentTemplate(title: "Incident", subtitle: "Security event response", symbolName: "flame", tint: .red, category: .security),
        ComponentTemplate(title: "Risk Register", subtitle: "Tracked security risk", symbolName: "list.bullet.clipboard", tint: .red, category: .security),
        ComponentTemplate(title: "Data Classification", subtitle: "Sensitivity level", symbolName: "tag", tint: .red, category: .security),
        ComponentTemplate(title: "Zero Trust", subtitle: "Verify every request", symbolName: "person.badge.shield.checkmark", tint: .red, category: .security),
        ComponentTemplate(title: "Malware", subtitle: "Hostile software", symbolName: "ladybug", tint: .red, category: .security),
        ComponentTemplate(title: "Phishing", subtitle: "Social engineering threat", symbolName: "envelope.badge.shield.half.filled", tint: .red, category: .security),
        ComponentTemplate(title: "Quarantine", subtitle: "Isolated system or file", symbolName: "lock.square", tint: .red, category: .security),
        ComponentTemplate(title: "Firewall Rule", subtitle: "Allow or deny traffic", symbolName: "firewall", tint: .red, category: .security),
        ComponentTemplate(title: "DLP", subtitle: "Data loss prevention", symbolName: "doc.text.magnifyingglass", tint: .red, category: .security),
        ComponentTemplate(title: "Key Rotation", subtitle: "Credential lifecycle", symbolName: "key.radiowaves.forward", tint: .red, category: .security),
        ComponentTemplate(title: "Forensics", subtitle: "Investigation evidence", symbolName: "magnifyingglass.circle", tint: .red, category: .security),
        ComponentTemplate(title: "Secure Baseline", subtitle: "Required hardening state", symbolName: "checkmark.shield.fill", tint: .red, category: .security)
    ]
}

struct BoardDocument: Equatable, Codable {
    static let currentSchemaVersion = 5

    var schemaVersion = BoardDocument.currentSchemaVersion
    var board: Board
}
