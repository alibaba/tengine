#include "hessian2_input.h"
#include "objects.h"
#include "hessian2_ext.h"
#include "utils.h"
#include <map>
#include <sstream>
#include <memory>

namespace hessian {

using namespace std;

hessian2_input::hessian2_input(const std::string* data)
  : _begin(data->c_str()), _curr(_begin), _end(_begin + data->length()) {}

hessian2_input::hessian2_input(const char* data, uint32_t size)
  : _begin(data), _curr(data), _end(data + size) {}

void hessian2_input::read_null() {
  uint8_t tag = parse_8bit();
  if (tag != 'N') {
    throw expect("null", tag);
  }
}

bool hessian2_input::read_bool() {
    uint8_t tag = parse_8bit();
    switch(tag) {
        case 56:
        case 57:
        case 58:
        case 59:
        case 61:
        case 62:
        case 63:
            parse_8bit();
            parse_8bit();
            return true;
        case 60:
            return 256 * parse_8bit() + parse_8bit() != 0;
        case 64:
        case 65:
        case 66:
        case 67:
        case 69:
        case 71:
        case 72:
        case 74:
        case 75:
        case 77:
        case 79:
        case 80:
        case 81:
        case 82:
        case 83:
        case 85:
        case 86:
        case 87:
        case 88:
        case 90:
        case 96:
        case 97:
        case 98:
        case 99:
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
        case 108:
        case 109:
        case 110:
        case 111:
        case 112:
        case 113:
        case 114:
        case 115:
        case 116:
        case 117:
        case 118:
        case 119:
        case 120:
        case 121:
        case 122:
        case 123:
        case 124:
        case 125:
        case 126:
        case 127:
        default:
            throw expect("boolean", tag);
        case 68:
            return parse_double() != 0.0;
        case 70:
            return false;
        case 73:
            return parse_32bit() != 0;
        case 76:
            return parse_64bit() != 0;
        case 78:
            return false;
        case 84:
            return true;
        case 89:
            return 16777216 * (long)parse_8bit() + 65536 * (long)parse_8bit() + (long)(256 * parse_8bit()) + (long)parse_8bit() != 0;
        case 91:
            return false;
        case 92:
            return true;
        case 93:
            return parse_8bit() != 0;
        case 94:
            return 256 * parse_8bit() + parse_8bit() != 0;
        case 95:
            {
                int mills = parse_32bit();
                return mills != 0;
            }
        case 128:
        case 129:
        case 130:
        case 131:
        case 132:
        case 133:
        case 134:
        case 135:
        case 136:
        case 137:
        case 138:
        case 139:
        case 140:
        case 141:
        case 142:
        case 143:
        case 144:
        case 145:
        case 146:
        case 147:
        case 148:
        case 149:
        case 150:
        case 151:
        case 152:
        case 153:
        case 154:
        case 155:
        case 156:
        case 157:
        case 158:
        case 159:
        case 160:
        case 161:
        case 162:
        case 163:
        case 164:
        case 165:
        case 166:
        case 167:
        case 168:
        case 169:
        case 170:
        case 171:
        case 172:
        case 173:
        case 174:
        case 175:
        case 176:
        case 177:
        case 178:
        case 179:
        case 180:
        case 181:
        case 182:
        case 183:
        case 184:
        case 185:
        case 186:
        case 187:
        case 188:
        case 189:
        case 190:
        case 191:
            return tag != 144;
        case 192:
        case 193:
        case 194:
        case 195:
        case 196:
        case 197:
        case 198:
        case 199:
        case 201:
        case 202:
        case 203:
        case 204:
        case 205:
        case 206:
        case 207:
            parse_8bit();
            return true;
        case 200:
            return parse_8bit() != 0;
        case 208:
        case 209:
        case 210:
        case 211:
        case 213:
        case 214:
        case 215:
            parse_8bit();
            parse_8bit();
            return true;
        case 212:
            return 256 * parse_8bit() + parse_8bit() != 0;
        case 216:
        case 217:
        case 218:
        case 219:
        case 220:
        case 221:
        case 222:
        case 223:
        case 224:
        case 225:
        case 226:
        case 227:
        case 228:
        case 229:
        case 230:
        case 231:
        case 232:
        case 233:
        case 234:
        case 235:
        case 236:
        case 237:
        case 238:
        case 239:
            return tag != 224;
        case 240:
        case 241:
        case 242:
        case 243:
        case 244:
        case 245:
        case 246:
        case 247:
        case 249:
        case 250:
        case 251:
        case 252:
        case 253:
        case 254:
        case 255:
            parse_8bit();
            return true;
        case 248:
            return parse_8bit() != 0;
    }
}

int32_t hessian2_input::read_int32() {
    uint8_t tag = parse_8bit();
    switch(tag) {
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
            return (tag - (60 << 16)) + 256 * parse_8bit() + parse_8bit();
        case 64:
        case 65:
        case 66:
        case 67:
        case 69:
        case 71:
        case 72:
        case 74:
        case 75:
        case 77:
        case 79:
        case 80:
        case 81:
        case 82:
        case 83:
        case 85:
        case 86:
        case 87:
        case 88:
        case 90:
        case 96:
        case 97:
        case 98:
        case 99:
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
        case 108:
        case 109:
        case 110:
        case 111:
        case 112:
        case 113:
        case 114:
        case 115:
        case 116:
        case 117:
        case 118:
        case 119:
        case 120:
        case 121:
        case 122:
        case 123:
        case 124:
        case 125:
        case 126:
        case 127:
        default:
            throw expect("integer", tag);
        case 68:
            return (int)parse_double();
        case 70:
            return 0;
        case 73:
        case 89:
            return (parse_8bit() << 24) + (parse_8bit() << 16) + (parse_8bit() << 8) + parse_8bit();
        case 76:
            return (int)parse_64bit();
        case 78:
            return 0;
        case 84:
            return 1;
        case 91:
            return 0;
        case 92:
            return 1;
        case 93:
            return parse_8bit();
        case 94:
            return (short)(256 * parse_8bit() + parse_8bit());
        case 95:
            {
                int mills = parse_32bit();
                return (int)(0.001 * (double)mills);
            }
        case 128:
        case 129:
        case 130:
        case 131:
        case 132:
        case 133:
        case 134:
        case 135:
        case 136:
        case 137:
        case 138:
        case 139:
        case 140:
        case 141:
        case 142:
        case 143:
        case 144:
        case 145:
        case 146:
        case 147:
        case 148:
        case 149:
        case 150:
        case 151:
        case 152:
        case 153:
        case 154:
        case 155:
        case 156:
        case 157:
        case 158:
        case 159:
        case 160:
        case 161:
        case 162:
        case 163:
        case 164:
        case 165:
        case 166:
        case 167:
        case 168:
        case 169:
        case 170:
        case 171:
        case 172:
        case 173:
        case 174:
        case 175:
        case 176:
        case 177:
        case 178:
        case 179:
        case 180:
        case 181:
        case 182:
        case 183:
        case 184:
        case 185:
        case 186:
        case 187:
        case 188:
        case 189:
        case 190:
        case 191:
            return tag - 144;
        case 192:
        case 193:
        case 194:
        case 195:
        case 196:
        case 197:
        case 198:
        case 199:
        case 200:
        case 201:
        case 202:
        case 203:
        case 204:
        case 205:
        case 206:
        case 207:
            return (tag - (200 << 8)) + parse_8bit();
        case 208:
        case 209:
        case 210:
        case 211:
        case 212:
        case 213:
        case 214:
        case 215:
            return (tag - (212 << 16)) + 256 * parse_8bit() + parse_8bit();
        case 216:
        case 217:
        case 218:
        case 219:
        case 220:
        case 221:
        case 222:
        case 223:
        case 224:
        case 225:
        case 226:
        case 227:
        case 228:
        case 229:
        case 230:
        case 231:
        case 232:
        case 233:
        case 234:
        case 235:
        case 236:
        case 237:
        case 238:
        case 239:
            return tag - 224;
        case 240:
        case 241:
        case 242:
        case 243:
        case 244:
        case 245:
        case 246:
        case 247:
        case 248:
        case 249:
        case 250:
        case 251:
        case 252:
        case 253:
        case 254:
        case 255:
            return (tag - (248 << 8)) + parse_8bit();
    }
}

int64_t hessian2_input::read_int64() {
    uint8_t tag = parse_8bit();
    switch(tag) {
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
            return (int64_t)(((tag - 60) << 16) + 256 * parse_8bit() + parse_8bit());
        case 64:
        case 65:
        case 66:
        case 67:
        case 69:
        case 71:
        case 72:
        case 74:
        case 75:
        case 77:
        case 79:
        case 80:
        case 81:
        case 82:
        case 83:
        case 85:
        case 86:
        case 87:
        case 88:
        case 90:
        case 96:
        case 97:
        case 98:
        case 99:
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
        case 108:
        case 109:
        case 110:
        case 111:
        case 112:
        case 113:
        case 114:
        case 115:
        case 116:
        case 117:
        case 118:
        case 119:
        case 120:
        case 121:
        case 122:
        case 123:
        case 124:
        case 125:
        case 126:
        case 127:
        default:
            throw expect("long", tag);
        case 68:
            return (int64_t)parse_double();
        case 70:
            return 0;
        case 73:
        case 89:
            return (int64_t)parse_32bit();
        case 76:
            return parse_64bit();
        case 78:
            return 0;
        case 84:
            return 1;
        case 91:
            return 0;
        case 92:
            return 1;
        case 93:
            return (int64_t)parse_8bit();
        case 94:
            return (int64_t)(256 * parse_8bit() + parse_8bit());
        case 95:
            {
                int mills = parse_32bit();
                return (int64_t)(0.001 * (double)mills);
            }
        case 128:
        case 129:
        case 130:
        case 131:
        case 132:
        case 133:
        case 134:
        case 135:
        case 136:
        case 137:
        case 138:
        case 139:
        case 140:
        case 141:
        case 142:
        case 143:
        case 144:
        case 145:
        case 146:
        case 147:
        case 148:
        case 149:
        case 150:
        case 151:
        case 152:
        case 153:
        case 154:
        case 155:
        case 156:
        case 157:
        case 158:
        case 159:
        case 160:
        case 161:
        case 162:
        case 163:
        case 164:
        case 165:
        case 166:
        case 167:
        case 168:
        case 169:
        case 170:
        case 171:
        case 172:
        case 173:
        case 174:
        case 175:
        case 176:
        case 177:
        case 178:
        case 179:
        case 180:
        case 181:
        case 182:
        case 183:
        case 184:
        case 185:
        case 186:
        case 187:
        case 188:
        case 189:
        case 190:
        case 191:
            return (int64_t)(tag - 144);
        case 192:
        case 193:
        case 194:
        case 195:
        case 196:
        case 197:
        case 198:
        case 199:
        case 200:
        case 201:
        case 202:
        case 203:
        case 204:
        case 205:
        case 206:
        case 207:
            return (int64_t)(((tag - 200) << 8) + parse_8bit());
        case 208:
        case 209:
        case 210:
        case 211:
        case 212:
        case 213:
        case 214:
        case 215:
            return (int64_t)(((tag - 212) << 16) + 256 * parse_8bit() + parse_8bit());
        case 216:
        case 217:
        case 218:
        case 219:
        case 220:
        case 221:
        case 222:
        case 223:
        case 224:
        case 225:
        case 226:
        case 227:
        case 228:
        case 229:
        case 230:
        case 231:
        case 232:
        case 233:
        case 234:
        case 235:
        case 236:
        case 237:
        case 238:
        case 239:
            return (int64_t)(tag - 224);
        case 240:
        case 241:
        case 242:
        case 243:
        case 244:
        case 245:
        case 246:
        case 247:
        case 248:
        case 249:
        case 250:
        case 251:
        case 252:
        case 253:
        case 254:
        case 255:
            return (int64_t)(((tag - 248) << 8) + parse_8bit());
    }
}

double hessian2_input::read_double() {
    uint8_t tag = parse_8bit();
    switch(tag) {
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
            return (double)(((tag - 60) << 16) + 256 * parse_8bit() + parse_8bit());
        case 64:
        case 65:
        case 66:
        case 67:
        case 69:
        case 71:
        case 72:
        case 74:
        case 75:
        case 77:
        case 79:
        case 80:
        case 81:
        case 82:
        case 83:
        case 85:
        case 86:
        case 87:
        case 88:
        case 90:
        case 96:
        case 97:
        case 98:
        case 99:
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
        case 108:
        case 109:
        case 110:
        case 111:
        case 112:
        case 113:
        case 114:
        case 115:
        case 116:
        case 117:
        case 118:
        case 119:
        case 120:
        case 121:
        case 122:
        case 123:
        case 124:
        case 125:
        case 126:
        case 127:
        default:
            throw expect("double", tag);
        case 68:
            return parse_double();
        case 70:
            return 0.0;
        case 73:
        case 89:
            return (double)parse_double();
        case 76:
            return (double)parse_64bit();
        case 78:
            return 0.0;
        case 84:
            return 1.0;
        case 91:
            return 0.0;
        case 92:
            return 1.0;
        case 93:
            return (double)parse_8bit();
        case 94:
            return (double)(256 * parse_8bit() + parse_8bit());
        case 95:
            {
                int mills = parse_32bit();
                return 0.001 * (double)mills;
            }
        case 128:
        case 129:
        case 130:
        case 131:
        case 132:
        case 133:
        case 134:
        case 135:
        case 136:
        case 137:
        case 138:
        case 139:
        case 140:
        case 141:
        case 142:
        case 143:
        case 144:
        case 145:
        case 146:
        case 147:
        case 148:
        case 149:
        case 150:
        case 151:
        case 152:
        case 153:
        case 154:
        case 155:
        case 156:
        case 157:
        case 158:
        case 159:
        case 160:
        case 161:
        case 162:
        case 163:
        case 164:
        case 165:
        case 166:
        case 167:
        case 168:
        case 169:
        case 170:
        case 171:
        case 172:
        case 173:
        case 174:
        case 175:
        case 176:
        case 177:
        case 178:
        case 179:
        case 180:
        case 181:
        case 182:
        case 183:
        case 184:
        case 185:
        case 186:
        case 187:
        case 188:
        case 189:
        case 190:
        case 191:
            return (double)(tag - 144);
        case 192:
        case 193:
        case 194:
        case 195:
        case 196:
        case 197:
        case 198:
        case 199:
        case 200:
        case 201:
        case 202:
        case 203:
        case 204:
        case 205:
        case 206:
        case 207:
            return (double)(((tag - 200) << 8) + parse_8bit());
        case 208:
        case 209:
        case 210:
        case 211:
        case 212:
        case 213:
        case 214:
        case 215:
            return (double)(((tag - 212) << 16) + 256 * parse_8bit() + parse_8bit());
        case 216:
        case 217:
        case 218:
        case 219:
        case 220:
        case 221:
        case 222:
        case 223:
        case 224:
        case 225:
        case 226:
        case 227:
        case 228:
        case 229:
        case 230:
        case 231:
        case 232:
        case 233:
        case 234:
        case 235:
        case 236:
        case 237:
        case 238:
        case 239:
            return (double)(tag - 224);
        case 240:
        case 241:
        case 242:
        case 243:
        case 244:
        case 245:
        case 246:
        case 247:
        case 248:
        case 249:
        case 250:
        case 251:
        case 252:
        case 253:
        case 254:
        case 255:
            return (double)(((tag - 248) << 8) + parse_8bit());
    }
}

int64_t hessian2_input::read_utc_date() {
    uint8_t tag = parse_8bit();

    if(tag == 'J') {
        return parse_64bit();
    } else if(tag == 'K') {
        return (int64_t)parse_32bit() * 60000;
    } else {
        throw expect("date", tag);
    }
}

std::string* hessian2_input::read_utf8_string(std::string *dest)
{
    Safeguard<string> safeguard(dest);
    if (dest == NULL) {
        dest = new string();
        safeguard.reset(dest);
    }
    uint8_t tag = parse_8bit();
    switch(tag) {
        case 0:
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
        case 8:
        case 9:
        case 10:
        case 11:
        case 12:
        case 13:
        case 14:
        case 15:
        case 16:
        case 17:
        case 18:
        case 19:
        case 20:
        case 21:
        case 22:
        case 23:
        case 24:
        case 25:
        case 26:
        case 27:
        case 28:
        case 29:
        case 30:
        case 31:
            {
                uint16_t len = tag - 0;
                parse_utf8_string(len, dest);
                safeguard.release();
                return dest;
            }
        case 32:
        case 33:
        case 34:
        case 35:
        case 36:
        case 37:
        case 38:
        case 39:
        case 40:
        case 41:
        case 42:
        case 43:
        case 44:
        case 45:
        case 46:
        case 47:
        case 52:
        case 53:
        case 54:
        case 55:
        case 64:
        case 65:
        case 66:
        case 67:
        case 69:
        case 71:
        case 72:
        case 74:
        case 75:
        case 77:
        case 79:
        case 80:
        case 81:
        case 85:
        case 86:
        case 87:
        case 88:
        case 90:
        case 96:
        case 97:
        case 98:
        case 99:
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
        case 108:
        case 109:
        case 110:
        case 111:
        case 112:
        case 113:
        case 114:
        case 115:
        case 116:
        case 117:
        case 118:
        case 119:
        case 120:
        case 121:
        case 122:
        case 123:
        case 124:
        case 125:
        case 126:
        case 127:
        default:
            throw expect("string", tag);
        case 48:
        case 49:
        case 50:
        case 51:
            {
                uint16_t len = (tag - 48) * 256 + parse_8bit();
                parse_utf8_string(len, dest);
                safeguard.release();
                return dest;
            }
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
            return new string(int32_to_string(((tag - 60) << 16) + 256 * parse_8bit() + parse_8bit()));
        case 68:
            return new string(double_to_string(parse_double()));
        case 70:
            return new string("false");
        case 73:
        case 89:
            return new string(int32_to_string(parse_32bit()));
        case 76:
            return new string(int32_to_string(parse_64bit()));
        case 78:
            return NULL;
        case 82:
            --_curr;
            return read_chunked_utf8_string();
        case 83:
            {
                uint16_t len = parse_16bit();
                parse_utf8_string(len, dest);
                safeguard.release();
                return dest;

            }
        case 84:
            return new string("true");
        case 91:
            return new string("0.0");
        case 92:
            return new string("1.0");
        case 93:
            return new string(int32_to_string(parse_8bit()));
        case 94:
            return new string(int32_to_string(256 * parse_8bit() + parse_8bit()));
        case 95:
            {
                int ch = parse_32bit();
                return new string(double_to_string(0.001 * (double)ch));
            }
        case 128:
        case 129:
        case 130:
        case 131:
        case 132:
        case 133:
        case 134:
        case 135:
        case 136:
        case 137:
        case 138:
        case 139:
        case 140:
        case 141:
        case 142:
        case 143:
        case 144:
        case 145:
        case 146:
        case 147:
        case 148:
        case 149:
        case 150:
        case 151:
        case 152:
        case 153:
        case 154:
        case 155:
        case 156:
        case 157:
        case 158:
        case 159:
        case 160:
        case 161:
        case 162:
        case 163:
        case 164:
        case 165:
        case 166:
        case 167:
        case 168:
        case 169:
        case 170:
        case 171:
        case 172:
        case 173:
        case 174:
        case 175:
        case 176:
        case 177:
        case 178:
        case 179:
        case 180:
        case 181:
        case 182:
        case 183:
        case 184:
        case 185:
        case 186:
        case 187:
        case 188:
        case 189:
        case 190:
        case 191:
            return new string(int32_to_string(tag - 144));
        case 192:
        case 193:
        case 194:
        case 195:
        case 196:
        case 197:
        case 198:
        case 199:
        case 200:
        case 201:
        case 202:
        case 203:
        case 204:
        case 205:
        case 206:
        case 207:
            return new string(int32_to_string(((tag - 200) << 8) + parse_8bit()));
        case 208:
        case 209:
        case 210:
        case 211:
        case 212:
        case 213:
        case 214:
        case 215:
            return new string(int32_to_string(((tag - 212) << 16) + 256 * parse_8bit() + parse_8bit()));
        case 216:
        case 217:
        case 218:
        case 219:
        case 220:
        case 221:
        case 222:
        case 223:
        case 224:
        case 225:
        case 226:
        case 227:
        case 228:
        case 229:
        case 230:
        case 231:
        case 232:
        case 233:
        case 234:
        case 235:
        case 236:
        case 237:
        case 238:
        case 239:
            return new string(int32_to_string(tag - 224));
        case 240:
        case 241:
        case 242:
        case 243:
        case 244:
        case 245:
        case 246:
        case 247:
        case 248:
        case 249:
        case 250:
        case 251:
        case 252:
        case 253:
        case 254:
        case 255:
            return new string(int32_to_string(((tag - 248) << 8) + parse_8bit()));
    }
}

string* hessian2_input::read_chunked_utf8_string(string* dest) {
    uint8_t tag = parse_8bit();

    if (tag == 'N') {
        return dest;
    }

    if (dest == NULL) {
        dest = new string();
    }

    Safeguard<string> safeguard(dest);

    while (tag == 'R') {
        uint16_t char_size = parse_16bit();
        parse_utf8_string(char_size, dest);
        tag = parse_8bit();
    }

    switch(tag) {
        case 0:
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
        case 8:
        case 9:
        case 10:
        case 11:
        case 12:
        case 13:
        case 14:
        case 15:
        case 16:
        case 17:
        case 18:
        case 19:
        case 20:
        case 21:
        case 22:
        case 23:
        case 24:
        case 25:
        case 26:
        case 27:
        case 28:
        case 29:
        case 30:
        case 31:
            {
                uint16_t char_size = tag - 0;
                parse_utf8_string(char_size, dest);
                safeguard.release();
                return dest;
            }
        case 32:
        case 33:
        case 34:
        case 35:
        case 36:
        case 37:
        case 38:
        case 39:
        case 40:
        case 41:
        case 42:
        case 43:
        case 44:
        case 45:
        case 46:
        case 47:
        case 52:
        case 53:
        case 54:
        case 55:
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
        case 64:
        case 65:
        case 66:
        case 67:
        case 68:
        case 69:
        case 70:
        case 71:
        case 72:
        case 73:
        case 74:
        case 75:
        case 76:
        case 77:
        case 78:
        case 79:
        case 80:
        case 81:
        default:
            throw expect("string", tag);
        case 48:
        case 49:
        case 50:
        case 51:
            {
                uint16_t char_size = ((tag - 48) << 8) + parse_8bit();
                parse_utf8_string(char_size, dest);
                safeguard.release();
                return dest;
            }
        case 83:
            {
                uint16_t char_size = parse_16bit();
                parse_utf8_string(char_size, dest);
                safeguard.release();
                return dest;
            }
    }
}

string* hessian2_input::read_bytes() {
    string *dest = new string();

    Safeguard<string> safeguard(dest);

    uint8_t tag = parse_8bit();
    int len;
    switch(tag) {
        case 32:
        case 33:
        case 34:
        case 35:
        case 36:
        case 37:
        case 38:
        case 39:
        case 40:
        case 41:
        case 42:
        case 43:
        case 44:
        case 45:
        case 46:
        case 47:
            len = tag - 32;
            parse_raw_bytes(len, dest);
            safeguard.release();
            return dest;
        case 48:
        case 49:
        case 50:
        case 51:
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
        case 64:
        case 67:
        case 68:
        case 69:
        case 70:
        case 71:
        case 72:
        case 73:
        case 74:
        case 75:
        case 76:
        case 77:
        default:
            throw expect("bytes", tag);
        case 52:
        case 53:
        case 54:
        case 55:
            len = (tag - 52) * 256 + parse_8bit();
            parse_raw_bytes(len, dest);
            safeguard.release();
            return dest;
        case 65:
            --_curr;
            safeguard.release();
            return read_chunked_bytes(dest);
        case 66:
            {
                uint16_t size = parse_16bit();
                parse_raw_bytes(size, dest);
                safeguard.release();
                return dest;
            }
        case 78:
            return NULL;
    }
    return NULL;
}

string* hessian2_input::read_chunked_bytes(string* dest) {
    uint8_t tag = parse_8bit();

    if (tag == 'N') {
        return dest;
    }

    if (dest == NULL) {
        dest = new string();
    }
    Safeguard<string> safeguard(dest);

    while (tag == 'A') {
        uint16_t byte_size = parse_16bit();
        parse_raw_bytes(byte_size, dest);
        tag = parse_8bit();
    }

    switch(tag) {
        case 32:
        case 33:
        case 34:
        case 35:
        case 36:
        case 37:
        case 38:
        case 39:
        case 40:
        case 41:
        case 42:
        case 43:
        case 44:
        case 45:
        case 46:
        case 47:
            {
                uint16_t size = tag - 32;
                parse_raw_bytes(size, dest);
                safeguard.release();
                return dest;
            }
        case 48:
        case 49:
        case 50:
        case 51:
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
        case 64:
        default:
            throw expect("byte[]", tag);
        case 52:
        case 53:
        case 54:
        case 55:
            {
                uint16_t size = (tag - 52) * 256 + parse_8bit();
                parse_raw_bytes(size, dest);
                safeguard.release();
                return dest;
            }
        case 66:
            {
                uint16_t size = parse_16bit();
                parse_raw_bytes(size, dest);
                safeguard.release();
                return dest;
            }
    }

    return NULL;
}

uint32_t hessian2_input::read_length() {
    throw io_exception("type is unsupported for the moment");
}

string hessian2_input::read_type() {
    throw io_exception("type is unsupported for the moment");
}

Object* hessian2_input::read_list(const string& classname) {
    throw io_exception("list is unsupported for the moment");
}

Object* hessian2_input::read_map(const string& classname) {
    uint8_t tag = parse_8bit();
    string type;

    switch (tag) {
        case 'H':
            break;
        case 'M':
            {
                string *tmp = read_utf8_string();
                type = *tmp;
                delete tmp;
                if (type.empty()) {
                    type = classname.empty() ? Map::DEFAULT_CLASSNAME : classname;
                }
            }
            break;
        case 'N':
            return NULL;
        //case 'R': return get_ref_object(parse_32bit());
        default:
            throw expect("map", tag);
    }

    hessian2_deserialize_pt ext = hessian2_get_deserializer(Object::EXT_MAP, type);

    if (ext) {
        return ext(type, *this);
    } else {
        Map* map = new Map(type);
        Safeguard<Map> safeguard(map);
        add_ref(map);

        while ((tag = peek()) != 'Z') {
            pair<Object*, bool> ret_key = read_object();
            pair<Object*, bool> ret_val = read_object();
            map->put(ret_key.first, ret_val.first, ret_key.second, ret_val.second);
        }

        ++_curr;
        safeguard.release();
        return map;
    }
}

pair<Object*, bool> hessian2_input::read_object() {
    uint8_t tag = peek();

    switch(tag) {
        case 0:
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
        case 8:
        case 9:
        case 10:
        case 11:
        case 12:
        case 13:
        case 14:
        case 15:
        case 16:
        case 17:
        case 18:
        case 19:
        case 20:
        case 21:
        case 22:
        case 23:
        case 24:
        case 25:
        case 26:
        case 27:
        case 28:
        case 29:
        case 30:
        case 31:
            return pair<Object*, bool>(new String(read_utf8_string(), true), true);
        case 32:
        case 33:
        case 34:
        case 35:
        case 36:
        case 37:
        case 38:
        case 39:
        case 40:
        case 41:
        case 42:
        case 43:
        case 44:
        case 45:
        case 46:
        case 47:
            return pair<Object*, bool>(new ByteArray(read_bytes(), true), true);
        case 48:
        case 49:
        case 50:
        case 51:
            return pair<Object*, bool>(new String(read_utf8_string(), true), true);
        case 52:
        case 53:
        case 54:
        case 55:
            return pair<Object*, bool>(new ByteArray(read_bytes(), true), true);
        case 56:
        case 57:
        case 58:
        case 59:
        case 60:
        case 61:
        case 62:
        case 63:
            return pair<Object*, bool>(new Long(read_int64()), true);
        case 64:
        case 69:
        case 71:
        case 80:
        case 90:
        default:
            throw expect("readObject: unknown code ", tag);
        case 65:
        case 66:
            return pair<Object*, bool>(new ByteArray(read_bytes(), true), true);
        case 67:
            throw io_exception("unsupported type readObjectDefinition");
        case 68:
            return pair<Object*, bool>(new Double(read_double()), true);
        case 70:
            return pair<Object*, bool>(new Boolean(read_bool()), true);
        case 72:
            return pair<Object*, bool>(read_map(), true);
        case 73:
            return pair<Object*, bool>(new Integer(read_int32()), true);
        case 74:
        case 75:
            return pair<Object*, bool>(new Date(read_utc_date()), true);
        case 76:
            return pair<Object*, bool>(new Long(read_int64()), true);
        case 77:
            return pair<Object*, bool>(read_map(), true);
        case 78:
            return pair<Object*, bool>(NULL, true);
        case 79:
            throw io_exception("unsupported readObjectInstance");
        case 81:
            return pair<Object*, bool>(read_ref(), true);
        case 82:
        case 83:
            return pair<Object*, bool>(new String(read_utf8_string(), true), true);
        case 84:
            return pair<Object*, bool>(new Boolean(read_bool()), true);
        case 85:
            return pair<Object*, bool>(read_list(), true);
        case 86:
            return pair<Object*, bool>(read_list(), true);
        case 87:
            return pair<Object*, bool>(read_list(), true);
        case 88:
            return pair<Object*, bool>(read_list(), true);
        case 89:
            return pair<Object*, bool>(new Long(read_int64()), true);
        case 91:
            return pair<Object*, bool>(new Double(read_double()), true);
        case 92:
            return pair<Object*, bool>(new Double(read_double()), true);
        case 93:
            return pair<Object*, bool>(new Double(read_double()), true);
        case 94:
            return pair<Object*, bool>(new Double(read_double()), true);
        case 95:
            return pair<Object*, bool>(new Double(read_double()), true);
        case 96:
        case 97:
        case 98:
        case 99:
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
        case 108:
        case 109:
        case 110:
        case 111:
            throw io_exception("unsupported readObjectInstance");
        case 112:
        case 113:
        case 114:
        case 115:
        case 116:
        case 117:
        case 118:
        case 119:
            return pair<Object*, bool>(read_list(), true);
        case 120:
        case 121:
        case 122:
        case 123:
        case 124:
        case 125:
        case 126:
        case 127:
            return pair<Object*, bool>(read_list(), true);
        case 128:
        case 129:
        case 130:
        case 131:
        case 132:
        case 133:
        case 134:
        case 135:
        case 136:
        case 137:
        case 138:
        case 139:
        case 140:
        case 141:
        case 142:
        case 143:
        case 144:
        case 145:
        case 146:
        case 147:
        case 148:
        case 149:
        case 150:
        case 151:
        case 152:
        case 153:
        case 154:
        case 155:
        case 156:
        case 157:
        case 158:
        case 159:
        case 160:
        case 161:
        case 162:
        case 163:
        case 164:
        case 165:
        case 166:
        case 167:
        case 168:
        case 169:
        case 170:
        case 171:
        case 172:
        case 173:
        case 174:
        case 175:
        case 176:
        case 177:
        case 178:
        case 179:
        case 180:
        case 181:
        case 182:
        case 183:
        case 184:
        case 185:
        case 186:
        case 187:
        case 188:
        case 189:
        case 190:
        case 191:
            return pair<Object*, bool>(new Integer(read_int32()), true);
        case 192:
        case 193:
        case 194:
        case 195:
        case 196:
        case 197:
        case 198:
        case 199:
        case 200:
        case 201:
        case 202:
        case 203:
        case 204:
        case 205:
        case 206:
        case 207:
            return pair<Object*, bool>(new Integer(read_int32()), true);
        case 208:
        case 209:
        case 210:
        case 211:
        case 212:
        case 213:
        case 214:
        case 215:
            return pair<Object*, bool>(new Integer(read_int32()), true);
        case 216:
        case 217:
        case 218:
        case 219:
        case 220:
        case 221:
        case 222:
        case 223:
        case 224:
        case 225:
        case 226:
        case 227:
        case 228:
        case 229:
        case 230:
        case 231:
        case 232:
        case 233:
        case 234:
        case 235:
        case 236:
        case 237:
        case 238:
        case 239:
            return pair<Object*, bool>(new Long(read_int64()), true);
        case 240:
        case 241:
        case 242:
        case 243:
        case 244:
        case 245:
        case 246:
        case 247:
        case 248:
        case 249:
        case 250:
        case 251:
        case 252:
        case 253:
        case 254:
        case 255:
            return pair<Object*, bool>(new Long(read_int64()), true);
    }

}

pair<Object*, bool> hessian2_input::read_object(const string& classname) {
    throw io_exception("object is unsupported for the moment");
}

int32_t hessian2_input::add_ref(Object* object) {
    _refs_list.push_back(object);
    return _refs_list.size();
}

Object* hessian2_input::read_ref() {
    return get_ref_object(parse_32bit());
}

Object* hessian2_input::get_ref_object(uint32_t ref_id) {
    if (ref_id >= _refs_list.size()) {
        ostringstream oss;
        oss << "the given reference (ref_id=" << ref_id
            << ") is not in the _refs_list (size=" << _refs_list.size() << ")";
        throw error(oss.str());
    }
    return _refs_list[ref_id];
}

double hessian2_input::parse_double() {
    return long_to_double(parse_64bit());
}

void hessian2_input::parse_utf8_string(uint32_t char_size, string* dest) {
    if (_curr + char_size - 1 >= _end) {
        throw error("hessian2_input::parse_utf8_string(): will reach EOF");
    }

    dest->reserve(dest->size() + char_size);

    while (char_size--) {
        if (eof()) {
            throw error("hessian2_input::parse_utf8_string(): reached EOF");
        }

        int ch = (uint8_t) *_curr++;

        if (ch < 0x80) {
            dest->push_back(ch);
        } else if ((ch & 0xe0) == 0xc0) {
            dest->push_back(ch);
            dest->push_back(*_curr++);
        } else if ((ch & 0xf0) == 0xe0) {
            dest->push_back(ch);
            dest->push_back(*_curr++);
            dest->push_back(*_curr++);
        } else {
            throw error("bad utf-8 encoding");
        }
    }
}

void hessian2_input::skip_object() {
    pair<Object*, bool> ret = read_object();
    if (ret.second) {
        delete ret.first;
    }
}

io_exception hessian2_input::expect(const string& expect, int ch) {
    ostringstream oss;
    oss << "expected " << expect;
    if (ch < 0) {
        oss << " but reached end of file";
    } else {
        oss << " but actually met " << hex << showbase << ch;
    }
    oss << " near position " << (uintptr_t)(_curr - _begin);
    return io_exception(oss.str());
}

io_exception hessian2_input::error(const string& expect) {
    ostringstream oss;
    oss << "error: " << expect << " near position " << (uintptr_t)(_curr - _begin);
    return io_exception(oss.str());
}

}
