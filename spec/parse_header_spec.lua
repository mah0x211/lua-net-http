local Parse = require('net.http.parse')
local ParseHeader = Parse.header

describe("test net.http.parse.request", function()
    it('can parse header lines that terminate by CRLF', function()
        local msg = 'Foo: foo-value\r\n' .. 'Bar: bar-value\r\n' .. '\r\n'
        local header = {}

        assert.are.equal(#msg, ParseHeader(msg, header))
        assert.are.same({foo = 'foo-value', bar = 'bar-value'}, header)
    end)

    it('can parse header lines that terminate by LF', function()
        local msg = 'Foo: foo-value\n' .. 'Bar: bar-value\n' .. '\n'
        local header = {}

        assert.are.equal(#msg, ParseHeader(msg, header))
        assert.are.same({foo = 'foo-value', bar = 'bar-value'}, header)
    end)

    it('ignore empty-value', function()
        local msg = 'Foo: foo-value\n' .. 'Bar: \n' .. 'Baz: baz-value\n' ..
                        'Qux: \n' .. '\n'
        local header = {}

        assert.are.equal(#msg, ParseHeader(msg, header))
        assert.are.same({foo = 'foo-value', baz = 'baz-value'}, header)
    end)

    it('insert multiple same name headers into array', function()
        local msg = 'Hello: world!\n' .. 'Host: example1.com\n' ..
                        'Host: example2.com\n' .. 'Host: example3.com\n' ..
                        'Host: 1.example.com 2.example.com\t3.example.com\n' ..
                        '\n'
        local header = {}

        assert.are.equal(#msg, ParseHeader(msg, header))
        assert.are.same({
            hello = 'world!',
            host = {
                'example1.com', 'example2.com', 'example3.com',
                '1.example.com 2.example.com\t3.example.com'},
        }, header)
    end)

    it('cannot parse header lines that not terminate by LF', function()
        local msg = 'Foo: foo-value\r' .. 'Bar: bar-value\r' .. '\r'

        assert.are.equal(Parse.EEOL, ParseHeader(msg, {}))
    end)

    it("can parse header lines from specified offset position", function()
        local line = 'Hello world'
        local msg = line .. 'Foo: foo-value\n' .. 'Bar: bar-value\n' .. '\n'
        local header = {}

        assert.are.equal(#msg, ParseHeader(msg, header, #line))
        assert.are.same({foo = 'foo-value', bar = 'bar-value'}, header)
    end)

    it("can limit the length of header line", function()
        local msg = 'Foo: foo-value\n' .. 'Bar: bar-value\n' .. '\n'

        assert.are.equal(Parse.EHDRLEN, ParseHeader(msg, {}, nil, 10))
    end)

    it("can limit the number of header line", function()
        local msg = 'Foo: foo-value\n' .. 'Bar: bar-value\n' ..
                        'Baz: baz-value\n' .. 'Qux: qux-value\n' .. '\n'
        local header = {}

        assert.are.equal(Parse.EHDRNUM, ParseHeader(msg, {}, nil, nil, 3))
        assert.are.equal(#msg, ParseHeader(msg, header, nil, nil, 4))
        assert.are.same({
            foo = 'foo-value',
            bar = 'bar-value',
            baz = 'baz-value',
            qux = 'qux-value',
        }, header)
    end)

    it("cannot parse invalide header name", function()
        local VALID_HKEY = {
        --  NUL = EAGAIN
            true,
            nil, nil, nil, nil, nil, nil, nil, nil, nil,
        --  LF = end of header
            true,
            nil, nil, nil, nil,
            nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil, nil,
        --        "                              (    )              ,              /
            '!', nil, '#', '$', '%', '&', '\'', nil, nil, '*', '+', nil, '-', '.', nil,
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
        --   :    ;    <    =    >    ?    @
            nil, nil, nil, nil, nil, nil, nil,
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
            'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
        --   [    \    ]
            nil, nil, nil, '^', '_', '`',
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
            'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
        --   {         }
            nil, '|', nil, '~'
        }

        for i = 0x0, 0x7e do
            if not VALID_HKEY[i + 1] then
                local c = string.char(i)

                assert.are.equal(Parse.EHDRNAME,
                                 ParseHeader(c .. 'Host: example.com\n\n', {}))
            end
        end
        assert.are.equal(Parse.EHDRNAME,
                         ParseHeader(' Host : example.com\n\n', {}))
        assert.are.equal(Parse.EHDRNAME,
                         ParseHeader('Host : example.com\n\n', {}))
    end)

    it("cannot parse invalide header value", function()
        local VCHAR = {
            nil, nil, nil, nil, nil, nil, nil, nil, nil,
        --  HT LF
            1, 1,
            nil, nil,
        --  CR
            1,
            nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil, nil, nil, nil, nil, nil,
        --  SP !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        --  nil  1  2  3  4  5  6  7  8  9
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        --  :  ;  <  =  >  ?  @
            1, 1, 1, 1, 1, 1, 1,
        --  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O  P  Q  R  S  T  U  V  W  X  Y
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        --  Z  [  \  ]  ^  _  `
            1, 1, 1, 1, 1, 1, 1,
        --  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o  p  q  r  s  t  u  v  w  x  y
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        --  z  {  |  }  ~
            1, 1, 1, 1, 1
        }

        for i = 0x0, 0x7e do
            if not VCHAR[i + 1] then
                local c = string.char(i)

                assert.are.equal(Parse.EHDRVAL, ParseHeader(
                                     'Host: ' .. c .. 'example.com\n\n', {}))
            end
        end
    end)
end)

