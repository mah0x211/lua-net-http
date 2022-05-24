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

function testcase.status_code()
    -- test that constains the http status code
    for name, code in pairs(STATUSES) do
        assert.equal(code, status[name])
    end
end

function testcase.toline()
    local toline = status.toline

    -- test that returns a status message
    for _, code in pairs(STATUSES) do
        assert.match(toline(code), '^' .. code .. ' ', false)
    end

    -- test that returns a status message with version number
    for _, code in pairs(STATUSES) do
        -- version 1.0
        assert.match(toline(code, 1), '^HTTP/1.0 ' .. code .. ' .+\r\n$', false)
        -- version 1.1
        assert.match(toline(code, 1.1), '^HTTP/1.1 ' .. code .. ' .+\r\n$',
                     false)
    end

    -- test that returns an error with unsupported code
    assert.match(toline(900), '900 Unknown Status Code')

    -- test that returns an error with unsupported version
    local err = assert.throws(toline, 100, 2)
    assert.match(err, 'unsupported version ')

    -- test that throw an erro with invalid arguments
    err = assert.throws(toline)
    assert.match(err, 'code must be integer')
    for _, code in ipairs({
        'hello',
        true,
        false,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        err = assert.throws(toline, code)
        assert.match(err, 'code must be integer')
        err = assert.throws(toline, 1, code)
        assert.match(err, 'unsupported version ')
    end
end

