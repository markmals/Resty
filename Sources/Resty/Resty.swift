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

public struct EndpointPublisher: Publisher {
    public typealias Output = Data
    public typealias Failure = Error
    
    var request: URLRequest
    var expectedStatusCode: Range<Int>
    
    public func receive<S>(subscriber: S) where S : Subscriber, Error == S.Failure, Output == S.Input {
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

extension EndpointPublisher {
    public init(
        _ method: Method,
        url: URL,
        accept: ContentType?,
        contentType: ContentType?,
        body: Data?,
        headers: [String: String] = [:],
        expectedStatusCode: Range<Int>,
        timeOutInterval: TimeInterval = 10,
        queryItems: [String: String] = [:]
    ) {
        var requestURL: URL
        
        if queryItems.isEmpty {
            requestURL = url
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
            components.queryItems = components.queryItems ?? []
            components.queryItems!.append(contentsOf: queryItems.map { URLQueryItem(name: $0.0, value: $0.1) })
            requestURL = components.url!
        }
    
        var request = URLRequest(url: requestURL)
    
        if let accept = accept {
            request.setValue(accept.rawValue, forHTTPHeaderField: "Accept")
        }
    
        if let contentType = contentType {
            request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }
    
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    
        request.timeoutInterval = timeOutInterval
        request.httpMethod = method.rawValue

        // body *needs* to be the last property that we set, because of this bug:
        // https://bugs.swift.org/browse/SR-6687
        request.httpBody = body
        
        self.request = request
        self.expectedStatusCode = expectedStatusCode
    }
}
