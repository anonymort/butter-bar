// TestFixtures — JSON traces and availability schedules for planner replay tests.
// Fixtures authored in T-PLANNER-FIXTURES; loader implemented in T-PLANNER-TRACE-LOADER.

import Foundation

/// Loads trace and expected-action fixtures from the TestFixtures bundle.
/// This is public so that PlannerCoreTests can access the resources without
/// needing to embed them in a separate bundle.
public enum FixtureLoader {

    /// Loads and decodes a trace JSON file by name (without extension).
    /// - Parameter name: e.g. "front-moov-mp4-001"
    /// - Throws: if the file is not found or JSON decoding fails.
    public static func loadTrace(named name: String) throws -> Trace {
        let data = try data(forResource: name, subdirectory: "traces")
        return try JSONDecoder().decode(Trace.self, from: data)
    }

    /// Loads and decodes an expected-actions JSON file by name (without extension).
    /// - Parameter name: e.g. "front-moov-mp4-001"
    /// - Throws: if the file is not found or JSON decoding fails.
    public static func loadExpected(named name: String) throws -> ExpectedActions {
        let data = try data(forResource: name, subdirectory: "expected")
        return try JSONDecoder().decode(ExpectedActions.self, from: data)
    }

    private static func data(forResource name: String, subdirectory: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: subdirectory
        ) else {
            throw FixtureError.notFound(name: name, subdirectory: subdirectory)
        }
        return try Data(contentsOf: url)
    }
}

public enum FixtureError: Error, CustomStringConvertible {
    case notFound(name: String, subdirectory: String)

    public var description: String {
        switch self {
        case .notFound(let name, let subdir):
            return "Fixture '\(name).json' not found in '\(subdir)' subdirectory of TestFixtures bundle."
        }
    }
}
