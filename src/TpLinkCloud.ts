import { v4 } from "uuid";
import axios from "axios";

interface ITpLinkCloudConstructorParams {
    username: string;
    password: string;
    termID?: string;
    appName?: string;
    appVer?: string;
    ospf?: string;
    netType?: string;
    locale?: string;
    userAgent?: string;
}

export class TpLinkCloud {
    public readonly username: string;
    public readonly password: string;
    public readonly termID: string;
    public readonly appName: string;
    public readonly appVer: string;
    public readonly ospf: string;
    public readonly netType: string;
    public readonly locale: string;
    public readonly userAgent: string;

    constructor(params: ITpLinkCloudConstructorParams) {
        this.username = params.username;
        this.password = params.password;
        this.termID = params.termID ?? v4();
        this.appName = params.appName ?? "Kasa_Android";
        this.appVer = params.appVer ?? "1.4.4.607";
        this.ospf = params.ospf ?? "Android+6.0.1";
        this.netType = params.netType ?? "wifi";
        this.locale = params.locale ?? "en_US";
        this.userAgent = params.userAgent ?? "Dalvik/2.1.0 (Linux; U; Android 6.0.1; A0001 Build/M4B30X)";
    }

    // @todo: return a TpLinkCloudSession object
    async login(): Promise<any> {
        // @todo: don't use hard-coded values for appName / appType, appVer, ospf, netType, locale, userAgent
        const request = {
            method: "POST",
            url: "https://wap.tplinkcloud.com",
            params: {
                appName: "Kasa_Android",
                termID: this.termID,
                appVer: "1.4.4.607",
                ospf: "Android+6.0.1",
                netType: "wifi",
                locale: "es_ES"
            },
            data: {
                method: "login",
                url: "https://wap.tplinkcloud.com",
                params: {
                    appType: "Kasa_Android",
                    cloudPassword: this.password,
                    cloudUserName: this.username,
                    terminalUUID: this.termID
                }
            },
            headers: {
                "User-Agent":
                    "Dalvik/2.1.0 (Linux; U; Android 6.0.1; A0001 Build/M4B30X)",
                "Content-Type": "application/json"
            }
        };

        const response = await axios(request);

        if ( ! response.data || response.data.error_code !== 0 ){
            throw new Error(`Login failed: ${response.data.error_code}`);
        }

        const token = response.data.result.token;

        return token;
    }
}
