import Foundation

extension OpenWearablesHealthSDK {
    /// Read the paired user's summaries using the same refresh lock as background uploads.
    public func fetchSummary(
        section: String,
        query: [String: String],
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard ["activity", "sleep", "workouts", "vitals"].contains(section),
              let user = userId, let base = apiBaseUrl, hasAuth,
              foregroundSession != nil,
              var components = URLComponents(string: "\(base)/sdk/users/\(user)/summaries/\(section)") else {
            completion(.failure(NSError(domain: "OpenWearables.Summaries", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Connect your account to view summaries."])))
            return
        }
        let allowedKeys: Set<String> = ["start_date", "end_date", "cursor", "limit"]
        components.queryItems = query.filter { allowedKeys.contains($0.key) }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            completion(.failure(URLError(.badURL)))
            return
        }
        fetchSummary(url: url, user: user, mayRefresh: true, completion: completion)
    }

    private func fetchSummary(
        url: URL, user: String, mayRefresh: Bool,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard userId == user, let credential = authCredential else {
            completion(.failure(URLError(.userAuthenticationRequired)))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        applyAuth(to: &request, credential: credential)
        foregroundSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard self.userId == user else {
                completion(.failure(URLError(.cancelled)))
                return
            }
            if let error = error { completion(.failure(error)); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && mayRefresh && !self.isApiKeyAuth {
                // An upload may already have refreshed the credential while this GET was in flight.
                if self.authCredential != credential {
                    self.fetchSummary(url: url, user: user, mayRefresh: false, completion: completion)
                    return
                }
                self.attemptTokenRefresh { outcome in
                    switch outcome {
                    case .success:
                        self.fetchSummary(url: url, user: user, mayRefresh: false, completion: completion)
                    case .authFailure:
                        completion(.failure(NSError(domain: "OpenWearables.Summaries", code: 401,
                            userInfo: [NSLocalizedDescriptionKey: "Your session expired. Reconnect to view summaries."])))
                    case .networkError:
                        completion(.failure(URLError(.cannotConnectToHost)))
                    }
                }
                return
            }
            guard (200...299).contains(status), let data = data else {
                completion(.failure(NSError(domain: "OpenWearables.Summaries", code: status,
                    userInfo: [NSLocalizedDescriptionKey: "Could not load summaries (HTTP \(status))."])))
                return
            }
            completion(.success(data))
        }.resume()
    }
}
