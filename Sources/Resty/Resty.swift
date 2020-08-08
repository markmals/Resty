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

public struct Request<Response: Decodable> {
    let method: Method
    let url: URL
    
    let responseType: Response.Type
    var decoder: JSONDecoder
    
    var accept: ContentType?
    var contentType: ContentType?
    var body: Data?
    var headers: [String: String] = [:]
    var expectedStatusCode: Range<Int> = 200..<300
    var timeOutInterval: TimeInterval = 10
    var queryItems: [String: String] = [:]
    
    /// A publisher that delivers the results of of a URL request.
    public func publisher() -> AnyPublisher<Response, Error> {
        var requestURL: URL
        
        if queryItems.isEmpty {
            requestURL = url
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
            components.queryItems = components.queryItems ?? []
            components.queryItems!.append(contentsOf: queryItems.map {
                URLQueryItem(name: $0.0, value: $0.1)
            })
            requestURL = components.url!
        }
    
        var nativeRequest = URLRequest(url: requestURL)
    
        if let accept = accept {
            nativeRequest.setValue(accept.rawValue, forHTTPHeaderField: "Accept")
        }
    
        if let contentType = contentType {
            nativeRequest.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }
    
        for (key, value) in headers {
            nativeRequest.setValue(value, forHTTPHeaderField: key)
        }
    
        nativeRequest.timeoutInterval = timeOutInterval
        nativeRequest.httpMethod = method.rawValue

        // The body *needs* to be the last property that we set, because of this bug:
        // https://bugs.swift.org/browse/SR-6687
        nativeRequest.httpBody = body
        
        return URLSession.shared
            .dataTaskPublisher(for: nativeRequest)
            .validate(with: expectedStatusCode)
            .tryMap { data -> Response in
                if responseType == Data.self {
                    return data as! Response
                } else {
                    return try decoder.decode(Response.self, from: data)
                }
            }
            .eraseToAnyPublisher()
    }
}


extension Request {
    private func chain(modifying closure: (inout Request) -> Void) -> Request {
        var request = self
        closure(&request)
        return request
    }
    
    private func chain<Value>(
        modifying keyPath: WritableKeyPath<Request, Value>,
        with value: Value
    ) -> Request {
        chain { $0[keyPath: keyPath] = value }
    }
    
    private func chain(
        merging keyPath: WritableKeyPath<Request, [String: String]>,
        with dictionary: [String: String]
    ) -> Request {
        // Override old dictionary values with new values
        chain { $0[keyPath: keyPath].merge(dictionary) { _, rhs in return rhs } }
    }
}

extension Request {
    /// Adds the Accept content type to the request.
    ///
    /// This will override any previous `accept` modifiers.
    public func accept(_ contentType: ContentType?) -> Request {
        chain(modifying: \.accept, with: contentType)
    }
    
    /// Adds the Content-Type to the request.
    ///
    /// This will override any previous `contentType` modifiers.
    public func contentType(_ contentType: ContentType?) -> Request {
        chain(modifying: \.contentType, with: contentType)
    }
    
    /// Adds the body data to the request.
    ///
    /// This will override any previous `body` modifiers.
    public func body(_ data: Data?) -> Request {
        chain(modifying: \.body, with: data)
    }
    
    /// Encodes the `Encodable` instance and adds its body data to the request.
    ///
    /// This will override any previous `body` modifiers.
    public func body<T: Encodable, E: TopLevelEncoder>(
        _ object: T?,
        encoder: E
    ) -> Request where E.Output == Data {
        body(try? encoder.encode(object))
    }
    
    /// Adds the headers to the request.
    ///
    /// This will override any previous `headers` modifiers using the same key.
    public func headers(_ headers: [String: String]) -> Request {
        chain(modifying: \.headers, with: headers)
    }
    
    /// Adds the authorization headers to the request.
    ///
    /// This will override any previous `headers` modifiers using the same key.
    public func authorization(_ auth: [String: String]) -> Request {
        headers(auth)
    }
    
    /// Adds the expected status code to the request.
    ///
    /// This will override any previous `expectedStatusCode` modifiers.
    public func expectedStatusCode(_ range: Range<Int>) -> Request {
        chain(modifying: \.expectedStatusCode, with: range)
    }
    
    /// Adds the time out interval to the request.
    ///
    /// This will override any previous `timeOutInterval` modifiers.
    public func timeOutInterval(_ interval: TimeInterval) -> Request {
        chain(modifying: \.timeOutInterval, with: interval)
    }
    
    /// Adds the query items to the request.
    ///
    /// This will override any previous `queryItems` modifiers using the same key.
    public func queryItems(_ items: [String: String]) -> Request {
        chain(merging: \.queryItems, with: items)
    }
}

public protocol API {
    var baseURL: URL { get }
    var decoder: JSONDecoder { get }
    var encoder: JSONEncoder { get }
}

extension API {
    var decoder: JSONDecoder { JSONDecoder() }
    var encoder: JSONEncoder { JSONEncoder() }
}

extension API {
    private func publisher<T: Decodable>(_ method: Method, for path: String) -> Request<T> {
        Request(
            method: method,
            url: baseURL.appendingPathComponent(path),
            responseType: T.self,
            decoder: decoder
        )
    }
    
    /// Returns a publisher that sends a GET request using the provided `path` and `baseURL` and outputs the response data
    public func get(path: String) -> Request<Data> {
        publisher(.get, for: path)
    }
    
    /// Returns a publisher that sends a GET request using the provided `path`, `baseURL`, and `decoder` and outputs the response object
    public func get<T: Decodable>(path: String) -> Request<T> {
        publisher(.get, for: path)
    }
    
    /// Returns a publisher that sends a POST request using the provided `path` and `baseURL` and outputs the response data
    public func post(path: String) -> Request<Data> {
        publisher(.post, for: path)
    }
    
    /// Returns a publisher that sends a POST request using the provided `path` and `baseURL` and outputs the response data
    public func post<T: Decodable>(path: String) -> Request<T> {
        publisher(.post, for: path)
    }
    
    /// Returns a publisher that sends a PUT request using the provided `path` and `baseURL` and outputs the response data
    public func put(path: String) -> Request<Data> {
        publisher(.put, for: path)
    }
    
    /// Returns a publisher that sends a PUT request using the provided `path` and `baseURL` and outputs the response data
    public func put<T: Decodable>(path: String) -> Request<T> {
        publisher(.put, for: path)
    }
    
    /// Returns a publisher that sends a PATCH request using the provided `path` and `baseURL` and outputs the response data
    public func patch(path: String) -> Request<Data> {
        publisher(.patch, for: path)
    }
    
    /// Returns a publisher that sends a PATCH request using the provided `path` and `baseURL` and outputs the response data
    public func patch<T: Decodable>(path: String) -> Request<T> {
        publisher(.patch, for: path)
    }
    
    /// Returns a publisher that sends a DELETE request using the provided `path` and `baseURL` and outputs the response data
    public func delete(path: String) -> Request<Data> {
        publisher(.delete, for: path)
    }
    
    /// Returns a publisher that sends a DELETE request using the provided `path` and `baseURL` and outputs the response data
    public func delete<T: Decodable>(path: String) -> Request<T> {
        publisher(.delete, for: path)
    }
}
