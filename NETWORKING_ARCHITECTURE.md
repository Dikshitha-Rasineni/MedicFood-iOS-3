# Networking

How a screen gets data, and how to add a new call.

Four files in `MedicFood/Networking/`, each with one job:

| File | Job |
|---|---|
| `APIConfiguration.swift` | Which server, what timeout, what headers |
| `APIEndpoint.swift` | Every call the app can make, as one enum |
| `HTTPRequestManager.swift` | Builds and sends the request, maps errors |
| `APIService.swift` | Decodes the response into domain types |

The rule that keeps them apart: **`HTTPRequestManager` knows HTTP and nothing
about medicines. `APIService` knows medicines and nothing about HTTP.** Neither
has to change when the other does.

---

## The flow

```
ViewModel
   │  calls a service protocol, e.g. MedicineServicing.medicines()
   ▼
Service  (Services/)
   │  names an endpoint case
   ▼
APIService
   │  fetch(_:as:) — decodes JSON into Medicine, DoseRecord, …
   ▼
HTTPRequestManager
   │  builds URLRequest, sends it, maps status codes to APIError
   ▼
URLSession
```

A view never touches any of this. It talks to a ViewModel, which talks to a
service protocol.

---

## Environments

`APIEnvironment` has three cases, each with its own base URL:

```swift
case development   // https://dev-api.medicfood.app/v1
case staging       // https://staging-api.medicfood.app/v1
case production    // https://api.medicfood.app/v1
```

`APIConfiguration.default` picks by build configuration:

```swift
#if DEBUG
    development
#else
    production
#endif
```

So a release build cannot accidentally ship pointed at a dev server. There is
no runtime switch and no environment picker — that is deliberate.

---

## Endpoints

Every call the app can make is a case on one enum. You can read the app's whole
API surface in a single file instead of grepping for `URLRequest`:

```swift
enum APIEndpoint {
    case signIn(email: String, password: String)
    case medicines
    case createMedicine(Medicine)
    case recordDose(DoseRecord)
    …
}
```

Each case supplies four things: `path`, `method`, `queryItems`, and `body()`.
Because the body is built next to the path, a request and its payload cannot
drift apart.

### Adding a call

1. Add a case to `APIEndpoint`.
2. Add its `path` and `method`. Add `queryItems` or `body()` if it needs them.
3. Call it from a service:

```swift
func medicines() async throws -> [Medicine] {
    try await api.fetch(.medicines)
}
```

That is the whole change. You do not touch `HTTPRequestManager`.

---

## Errors

`APIError` is a typed enum, not a string:

```swift
case notConnected, timedOut, unauthorized, notFound
case server(status: Int, message: String?)
case decoding(String), invalidURL, unknown(String)
```

Status codes are mapped once, in `HTTPRequestManager.send`:

| Status | Becomes |
|---|---|
| 200–299 | the response data |
| 401, 403 | `.unauthorized` |
| 404 | `.notFound` |
| anything else | `.server(status:message:)`, message pulled from the JSON body |

Every case carries an `errorDescription` written for a patient to read, so a
ViewModel can show `error.errorDescription` directly. `isRetryable` says whether
trying again could plausibly work — offline and 5xx yes, a wrong password no.

This matters because the Flutter version had 329 `try`/`catch` blocks, many of
which caught an error, printed it, and carried on. A failed request looked
exactly like one that returned nothing.

---

## Response envelope

The backend wraps responses:

```json
{ "success": true, "message": null, "data": { … } }
```

`ResponseModel<T>` decodes that. Use it when the server sends the envelope, and
decode the bare type when it does not:

```swift
let response: ResponseModel<[Medicine]> = try await api.fetch(.medicines)
let medicines = response.data ?? []
```

`APIService` sets `.iso8601` dates and `.convertFromSnakeCase` keys, so
`start_date` from the server lands in `startDate` without a `CodingKeys` block.

---

## Public drug APIs

Drug lookup does not go through `APIEnvironment` — it calls two free public
services that need no key:

- **RxNorm** (`rxnav.nlm.nih.gov/REST`) — name → RxCUI resolution, fuzzy matching
- **openFDA** (`api.fda.gov/drug/label.json`) — label text, warnings, dosage

They are declared separately in `PublicAPI` because they are reference data,
not this app's backend. `MockDrugInfoService` currently serves sample data;
because no key is involved, `LiveDrugInfoService` is the easiest service to
switch on first.

---

## Testing without a network

`HTTPRequesting` is a protocol, so `APIService` can be built against a fake:

```swift
struct FakeRequester: HTTPRequesting {
    let data: Data
    func send(_ endpoint: APIEndpoint) async throws -> Data { data }
}

let api = APIService(requester: FakeRequester(data: sampleJSON))
```

One level up, the service protocols in `Services/` mean a ViewModel test never
reaches this layer at all — see `MedicFoodTests/DashboardViewModelTests.swift`,
which exercises the whole dashboard with no network involved.

---

## Currently mock

`ServiceContainer.mock()` is what the app runs on today, so it works offline
from a fresh clone with no secrets. The networking layer above is written and
compiles, but is not yet on a live server.

To switch a service over: write the live implementation next to the mock, and
change that one line in `ServiceContainer`. Nothing else in the app moves.

**Never put an API key in the app bundle.** The Flutter version shipped its
Gemini key in a bundled `.env`, which anyone could extract from the IPA. Keys
belong on a server.
