local Status = require('net.http.status')
local STATUS_CODE = {
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

describe('test net.http.status', function()
    it('has http status code constants', function()
        for name, code in pairs( STATUS_CODE ) do
            assert.is_equal( code, Status[name] )
        end
    end)

    it('cannot to pass a non-numeric arguments', function()
        for _, code in ipairs({
            'hello',
            true,
            false,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                Status.toline( code )
            end)
            assert.has_error(function()
                Status.toline( 1, code )
            end)
        end

        assert.has_error(function()
            Status.toline( nil )
        end)
    end)

    it('cannot pass an unknown status-code', function()
        local msg, err = Status.toline( 900 )
        assert.is_nil(msg)
        assert.is_not_nil(err)
    end)

    it('cannot pass a version number other than 1.0 or 1.1', function()
        local msg, err = Status.toline( 100, 2 )
        assert.is_nil(msg)
        assert.is_not_nil(err)
    end)

    it('returns a status message', function()
        for _, code in pairs( STATUS_CODE ) do
            local msg = Status.toline( code )

            assert.is_equal( 'string', type( msg ) )
            assert.is_equal( 1, string.find( msg, code .. ' ', 1, true ) )
        end
    end)

    it('returns a status message with version number', function()
        for _, code in pairs( STATUS_CODE ) do
            local msg = Status.toline( code, 1 )

            -- version 1.0
            assert.is_equal( 'string', type( msg ) )
            assert.is_equal( 1, string.find( msg, 'HTTP/1.0 ', 1, true ) )
            assert.is_equal( 10, string.find( msg, code .. ' ', 1, true ) )

            -- version 1.1
            msg = Status.toline( code, 1.1 )
            assert.is_equal( 'string', type( msg ) )
            assert.is_equal( 1, string.find( msg, 'HTTP/1.1 ', 1, true ) )
            assert.is_equal( 10, string.find( msg, code .. ' ', 1, true ) )
        end
    end)
end)

