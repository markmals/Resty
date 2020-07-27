import Foundation
import Combine

extension URLSession.DataTaskPublisher {
    func validate(with expectedStatusCode: Range<Int>) -> AnyPublisher<Data, Error> {
        tryMap { (data: Data, response: URLResponse) -> Data in
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
        .eraseToAnyPublisher()
    }
}

enum Method: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// An entity header used to indicate the media type of the resource.
public enum ContentType: String {
    /// The JSON content type.
    case json = "application/json"
    /// The XML content type.
    case xml = "application/xml"
    /// The Form Encoded content type.
    case urlencoded = "application/x-www-form-urlencoded"
}

struct Request {
    var accept: ContentType?
    var contentType: ContentType?
    var body: Data?
    var headers: [String: String] = [:]
    var expectedStatusCode: Range<Int> = 200..<300
    var timeOutInterval: TimeInterval = 10
    var queryItems: [String: String] = [:]
}

/// A publisher that delivers the results of of a URL request.
public struct RequestPublisher: Publisher {
    public typealias Output = Data
    public typealias Failure = Error
    
    var method: Method
    var url: URL
    var request = Request()
    
    var nativeRequest: URLRequest {
        var requestURL: URL
        
        if request.queryItems.isEmpty {
            requestURL = url
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
            components.queryItems = components.queryItems ?? []
            components.queryItems!.append(contentsOf: request.queryItems.map {
                URLQueryItem(name: $0.0, value: $0.1)
            })
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

        // The body *needs* to be the last property that we set, because of this bug:
        // https://bugs.swift.org/browse/SR-6687
        req.httpBody = request.body
        
        return req
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Error == S.Failure, Data == S.Input {
        URLSession.shared
            .dataTaskPublisher(for: nativeRequest)
            .validate(with: request.expectedStatusCode)
            .receive(subscriber: subscriber)
    }
}

extension RequestPublisher {
    private func chain(modifying closure: (inout Request) -> Void) -> RequestPublisher {
        var publisher = self
        var req = request
        closure(&req)
        publisher.request = req
        return publisher
    }
    
    private func chain<Value>(
        modifying keyPath: WritableKeyPath<Request, Value>,
        with value: Value
    ) -> RequestPublisher {
        chain { $0[keyPath: keyPath] = value }
    }
    
    private func chain(
        merging keyPath: WritableKeyPath<Request, [String: String]>,
        with dictionary: [String: String]
    ) -> RequestPublisher {
        // Override old dictionary values with new values
        chain { $0[keyPath: keyPath].merge(dictionary) { _, rhs in return rhs } }
    }
}

extension RequestPublisher {
    /// Adds the Accept content type to the request.
    ///
    /// This will override any previous `accept` modifiers.
    public func accept(_ contentType: ContentType?) -> RequestPublisher {
        chain(modifying: \.accept, with: contentType)
    }
    
    /// Adds the Content-Type to the request.
    ///
    /// This will override any previous `contentType` modifiers.
    public func contentType(_ contentType: ContentType?) -> RequestPublisher {
        chain(modifying: \.contentType, with: contentType)
    }
    
    /// Adds the body data to the request.
    ///
    /// This will override any previous `body` modifiers.
    public func body(_ data: Data?) -> RequestPublisher {
        chain(modifying: \.body, with: data)
    }
    
    /// Encodes the `Encodable` instance and adds its body data to the request.
    ///
    /// This will override any previous `body` modifiers.
    public func body<T: Encodable, E: TopLevelEncoder>(
        _ object: T?,
        encoder: E
    ) -> RequestPublisher where E.Output == Data {
        body(try? encoder.encode(object))
    }
    
    /// Adds the headers to the request.
    ///
    /// This will override any previous `headers` modifiers using the same key.
    public func headers(_ headers: [String: String]) -> RequestPublisher {
        chain(modifying: \.headers, with: headers)
    }
    
    /// Adds the authorization headers to the request.
    ///
    /// This will override any previous `headers` modifiers using the same key.
    public func authorization(_ auth: [String: String]) -> RequestPublisher {
        headers(auth)
    }
    
    /// Adds the expected status code to the request.
    ///
    /// This will override any previous `expectedStatusCode` modifiers.
    public func expectedStatusCode(_ range: Range<Int>) -> RequestPublisher {
        chain(modifying: \.expectedStatusCode, with: range)
    }
    
    /// Adds the time out interval to the request.
    ///
    /// This will override any previous `timeOutInterval` modifiers.
    public func timeOutInterval(_ interval: TimeInterval) -> RequestPublisher {
        chain(modifying: \.timeOutInterval, with: interval)
    }
    
    /// Adds the query items to the request.
    ///
    /// This will override any previous `queryItems` modifiers using the same key.
    public func queryItems(_ items: [String: String]) -> RequestPublisher {
        chain(merging: \.queryItems, with: items)
    }
}

public protocol API {
    var baseURL: URL { get }
}

extension API {
    private func publisher(_ method: Method, for path: String) -> RequestPublisher {
        RequestPublisher(
            method: method,
            url: baseURL.appendingPathComponent(path)
        )
    }
    
    /// Returns a publisher that sends a GET request using the provided `path` and `baseURL` and outputs the response data
    public func get(path: String) -> RequestPublisher {
        publisher(.get, for: path)
    }
    
    /// Returns a publisher that sends a POST request using the provided `path` and `baseURL` and outputs the response data
    public func post(path: String) -> RequestPublisher {
        publisher(.post, for: path)
    }
    
    /// Returns a publisher that sends a PUT request using the provided `path` and `baseURL` and outputs the response data
    public func put(path: String) -> RequestPublisher {
        publisher(.put, for: path)
    }
    
    /// Returns a publisher that sends a PATCH request using the provided `path` and `baseURL` and outputs the response data
    public func patch(path: String) -> RequestPublisher {
        publisher(.patch, for: path)
    }
    
    /// Returns a publisher that sends a DELETE request using the provided `path` and `baseURL` and outputs the response data
    public func delete(path: String) -> RequestPublisher {
        publisher(.delete, for: path)
    }
}
