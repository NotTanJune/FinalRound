import Foundation

struct JobPost: Identifiable, Hashable, Codable {
    let id: UUID
    let role: String
    let company: String
    let location: String
    let salary: String
    let tags: [String]
    let description: String?
    let responsibilities: [String]?
    let category: String?
    let logoName: String // In a real app this would be a URL
    
    init(role: String, company: String, location: String, salary: String, tags: [String], description: String? = nil, responsibilities: [String]? = nil, category: String? = nil, logoName: String, id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.company = company
        self.location = location
        self.salary = salary
        self.tags = tags
        self.description = description
        self.responsibilities = responsibilities
        self.category = category
        self.logoName = logoName
    }
    
    static let examples: [JobPost] = [
        JobPost(
            role: "Senior Procurement Analyst",
            company: "Zephyr",
            location: "California",
            salary: "$78,000",
            tags: ["Accounting", "Software"],
            logoName: "briefcase.fill"
        ),
        JobPost(
            role: "Senior UI Artist",
            company: "Netflix",
            location: "California",
            salary: "$120,000",
            tags: ["Art & Design", "Digital Entertainment"],
            logoName: "paintpalette.fill"
        ),
        JobPost(
            role: "Product Designer",
            company: "Linear",
            location: "Remote",
            salary: "$140,000",
            tags: ["Design", "Product"],
            logoName: "pencil.circle.fill"
        )
    ]
}
