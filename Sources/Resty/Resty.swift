import Foundation
import Combine

struct Post: Codable {}

struct Reddit: API {
    let base = URL(string: "https://www.reddit.com")!
    var apiKey = "**********"
    var authHeader: [String: String] {
        ["Authorization": "BEARER \(apiKey)"]
    }
    
    func getHomePosts(for subreddits: [String]) -> AnyPublisher<[Post], Error> {
        get("r/\(subreddits.joined(separator: "+"))/.json")
    }
    
    func upload(content: Post) -> AnyPublisher<(), Error> {
        Just(content)
            .encode(encoder: JSONEncoder())
            .flatMap { post("/some/postable/path", body: $0) }
            .eraseToAnyPublisher()
    }
}

protocol API {
    var base: URL { get }
}

extension API {
    var authorizationHeader: [String: String] { [:] }
    
    private func merging(_ lhs: [String: String], _ rhs: [String: String]) -> [String: String] {
        var merged = lhs
        merged.merge(rhs) { (lhs, rhs) in return rhs }
        return merged
    }
    
    func get<Response: Decodable>(
        _ path: String = "/",
        accept: ContentType? = nil,
        contentType: ContentType? = nil,
        body: Data? = nil,
        headers: [String: String] = [:],
        expectedStatusCode: Range<Int> = 200..<300,
        timeOutInterval: TimeInterval = 10,
        queryItems: [String: String] = [:]
    ) -> AnyPublisher<Response, Error> {
        EndpointPublisher(.get,
            url: base.appendingPathComponent(path),
            accept: accept,
            contentType: contentType,
            body: body,
            headers: merging(headers, authorizationHeader),
            expectedStatusCode: expectedStatusCode,
            timeOutInterval: timeOutInterval,
            queryItems: queryItems
        )
        .decode(type: Response.self, decoder: JSONDecoder())
        .eraseToAnyPublisher()
    }
    
    func post(
        _ path: String = "/",
        accept: ContentType? = nil,
        contentType: ContentType? = nil,
        body: Data? = nil,
        headers: [String: String] = [:],
        expectedStatusCode: Range<Int> = 200..<300,
        timeOutInterval: TimeInterval = 10,
        queryItems: [String: String] = [:]
    ) -> AnyPublisher<(), Error> {
        EndpointPublisher(.post,
            url: base.appendingPathComponent(path),
            accept: accept,
            contentType: contentType,
            body: body,
            headers: merging(headers, authorizationHeader),
            expectedStatusCode: expectedStatusCode,
            timeOutInterval: timeOutInterval,
            queryItems: queryItems
        )
        .map { _ in }
        .eraseToAnyPublisher()
    }
    
    func post<Response: Decodable>(
        _ path: String = "/",
        accept: ContentType? = nil,
        contentType: ContentType? = nil,
        body: Data? = nil,
        headers: [String: String] = [:],
        expectedStatusCode: Range<Int> = 200..<300,
        timeOutInterval: TimeInterval = 10,
        queryItems: [String: String] = [:]
    ) -> AnyPublisher<Response, Error> {
        EndpointPublisher(.post,
            url: base.appendingPathComponent(path),
            accept: accept,
            contentType: contentType,
            body: body,
            headers: merging(headers, authorizationHeader),
            expectedStatusCode: expectedStatusCode,
            timeOutInterval: timeOutInterval,
            queryItems: queryItems
        )
        .decode(type: Response.self, decoder: JSONDecoder())
        .eraseToAnyPublisher()
    }
}

//typealias Endpoint<Output> = AnyPublisher<Output, Error>

struct Request {
    var accept: ContentType?
    var contentType: ContentType?
    var body: Data?
    var headers: [String: String] = [:]
    var expectedStatusCode: Range<Int> = 200..<300
    var timeOutInterval: TimeInterval = 10
    var queryItems: [String: String] = [:]
}

protocol EndpointPublisher: Publisher {
    var nativeRequest: URLRequest { get }
    
    init(url: URL, request: Request)
}

struct GetPublisher: EndpointPublisher {
    typealias Output = Data
    typealias Failure = Error
    
    let upstream: DataPublisher
    var nativeRequest: URLRequest { upstream.request }
    
    init(url: URL, request: Request) {
        upstream = DataPublisher(method: .get, url: url, request: request)
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Error == S.Failure, Data == S.Input {
        upstream.receive(subscriber: subscriber)
    }
}

public struct DataPublisher: Publisher {
    public typealias Output = Data
    public typealias Failure = Error
    
    var request: URLRequest
    var expectedStatusCode: Range<Int>
    
    init(method: Method, url: URL, request: Request) {
        var requestURL: URL
        
        if request.queryItems.isEmpty {
            requestURL = url
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
            components.queryItems = components.queryItems ?? []
            components.queryItems!.append(contentsOf: request.queryItems.map { URLQueryItem(name: $0.0, value: $0.1) })
            requestURL = components.url!
        }
    
        var req = URLRequest(url: requestURL)
    
        if let accept = request.accept {
            req.setValue(accept.rawValue, forHTTPHeaderField: "Accept")
        }
    
        if let contentType = request.contentType {
            req.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }
    
        for (key, value) in request.headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
    
        req.timeoutInterval = request.timeOutInterval
        req.httpMethod = method.rawValue

        // body *needs* to be the last property that we set, because of this bug:
        // https://bugs.swift.org/browse/SR-6687
        req.httpBody = request.body
        
        self.request = req
        self.expectedStatusCode = request.expectedStatusCode
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Error == S.Failure, Data == S.Input {
        URLSession.shared
            .dataTaskPublisher(for: request)
            .tryMap { (data: Data, response: URLResponse) -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    // FIXME: Throw a better error
                    throw URLError(.unknown)
                }

                guard httpResponse.statusCode >= expectedStatusCode.min()! &&
                        httpResponse.statusCode < expectedStatusCode.max()! else {
                    // FIXME: Throw a better error
                    throw URLError(.unknown)
                }

                return data
            }
            .mapError { $0 as Error }
            .receive(subscriber: subscriber)
    }
}

public enum Method: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public enum ContentType: String {
    case json = "application/json"
    case xml = "application/xml"
    case urlencoded = "application/x-www-form-urlencoded"
}
