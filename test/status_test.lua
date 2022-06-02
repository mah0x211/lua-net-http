require('luacov')
local testcase = require('testcase')
local status = require('net.http.status')
local STATUSES = {
    --- status names
    -- 1×× Informational
    CONTINUE = 100,
    SWITCHING_PROTOCOLS = 101,
    PROCESSING = 102,
    -- 2×× Success
    OK = 200,
    CREATED = 201,
    ACCEPTED = 202,
    NON_AUTHORITATIVE_INFORMATION = 203,
    NO_CONTENT = 204,
    RESET_CONTENT = 205,
    PARTIAL_CONTENT = 206,
    MULTI_STATUS = 207,
    ALREADY_REPORTED = 208,
    IM_USED = 226,
    -- 3×× Redirection
    MULTIPLE_CHOICES = 300,
    MOVED_PERMANENTLY = 301,
    FOUND = 302,
    SEE_OTHER = 303,
    NOT_MODIFIED = 304,
    USE_PROXY = 305,
    TEMPORARY_REDIRECT = 307,
    PERMANENT_REDIRECT = 308,
    -- 4×× Client Error
    BAD_REQUEST = 400,
    UNAUTHORIZED = 401,
    PAYMENT_REQUIRED = 402,
    FORBIDDEN = 403,
    NOT_FOUND = 404,
    METHOD_NOT_ALLOWED = 405,
    NOT_ACCEPTABLE = 406,
    PROXY_AUTHENTICATION_REQUIRED = 407,
    REQUEST_TIMEOUT = 408,
    CONFLICT = 409,
    GONE = 410,
    LENGTH_REQUIRED = 411,
    PRECONDITION_FAILED = 412,
    PAYLOAD_TOO_LARGE = 413,
    REQUEST_URI_TOO_LONG = 414,
    UNSUPPORTED_MEDIA_TYPE = 415,
    REQUESTED_RANGE_NOT_SATISFIABLE = 416,
    EXPECTATION_FAILED = 417,
    IM_A_TEAPOT = 418,
    MISDIRECTED_REQUEST = 421,
    UNPROCESSABLE_ENTITY = 422,
    LOCKED = 423,
    FAILED_DEPENDENCY = 424,
    UPGRADE_REQUIRED = 426,
    PRECONDITION_REQUIRED = 428,
    TOO_MANY_REQUESTS = 429,
    REQUEST_HEADER_FIELDS_TOO_LARGE = 431,
    UNAVAILABLE_FOR_LEGAL_REASONS = 451,
    -- 5×× Server Error
    INTERNAL_SERVER_ERROR = 500,
    NOT_IMPLEMENTED = 501,
    BAD_GATEWAY = 502,
    SERVICE_UNAVAILABLE = 503,
    GATEWAY_TIMEOUT = 504,
    HTTP_VERSION_NOT_SUPPORTED = 505,
    VARIANT_ALSO_NEGOTIATES = 506,
    INSUFFICIENT_STORAGE = 507,
    LOOP_DETECTED = 508,
    NOT_EXTENDED = 510,
    NETWORK_AUTHENTICATION_REQUIRED = 511,
};

function testcase.name2code()
    -- test that get status code from status name
    for name, code in pairs(STATUSES) do
        assert.equal(status.name2code(name), code)
    end

    -- test that return nil if unknown status name
    assert.is_nil(status.name2code('HELLO'))

    -- test that throw an error if status name is not string
    local err = assert.throws(status.name2code, {})
    assert.match(err, 'name must be string')
end

function testcase.code2name()
    -- test that get status name from status code
    for name, code in pairs(STATUSES) do
        assert.equal(status.code2name(code), name)
    end

    -- test that return nil if unknown status code
    assert.is_nil(status.code2name(900))

    -- test that throw an error if status code is not integer
    local err = assert.throws(status.code2name, 1.1)
    assert.match(err, 'code must be integer')
end

function testcase.toline()
    local toline = status.toline

    -- test that generate status-line from status code
    assert.equal(toline(100), '100 Continue\r\n')
    for _, code in pairs(STATUSES) do
        assert.match(toline(code), '^' .. code .. ' ', false)
    end

    -- test that generate status-line from status code and version
    for _, code in pairs(STATUSES) do
        -- version 1.0
        assert.match(toline(code, 1), '^HTTP/1.0 ' .. code .. ' .+\r\n$', false)
        -- version 1.1
        assert.match(toline(code, 1.1), '^HTTP/1.1 ' .. code .. ' .+\r\n$',
                     false)
    end

    -- test that generate status-line from unknown status code
    assert.equal(toline(900), '900 Unknown Status\r\n')

    -- test that generate status-line from unknown status code and version
    assert.equal(toline(900, 12.20), 'HTTP/12.2 900 Unknown Status\r\n')

    -- test that generate status-line from unknown status code and reason
    assert.equal(toline(900, 1.1, 'My Status'), 'HTTP/1.1 900 My Status\r\n')

    -- test that throw an error if code is invalid
    local err = assert.throws(toline, 200.1)
    assert.match(err, 'code must be integer')

    -- test that throw an error if version is invalid
    err = assert.throws(toline, 100, 0 / 0)
    assert.match(err, 'version must be finite-number')

    -- test that throw an error if reason is invalid
    err = assert.throws(toline, 100, nil, true)
    assert.match(err, 'reason must be the following string: ')
    err = assert.throws(toline, 100, nil, 'hello world!')
    assert.match(err, 'reason must be the following string: ')
end

