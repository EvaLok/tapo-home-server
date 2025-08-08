import axios from "axios";

export class TpLinkCloudSession {
    public readonly token: string;
    public readonly termID: string;
    public readonly appName: string;
    public readonly appVer: string;
    public readonly ospf: string;
    public readonly netType: string;
    public readonly locale: string;
    public readonly userAgent: string;

    constructor(
        params: ITpLinkCloudConstructorParams & ITpLinkCloudProperties
    ) {
        this.token = params.token;
        this.termID = params.termID;
        this.appName = params.appName;
        this.appVer = params.appVer;
        this.ospf = params.ospf;
        this.netType = params.netType;
        this.locale = params.locale;
        this.userAgent = params.userAgent;
    }

    async getDeviceList(): Promise<Array<ITpLinkCloudDeviceListItem>> {
        const response = await this.makeRequest("getDeviceList", "https://wap.tplinkcloud.com");

        if ( ! response.deviceList ) {
            throw new Error("No device list found in response");
        }

        return response.deviceList || [];
    }

    async getDeviceInfo( device: ITpLinkCloudDeviceListItem ) : Promise<ITpLinkCloudDeviceListItem> {
        const response = await this.makeRequest(
            "getDeviceInfo",
            device.appServerUrl,
            {
                deviceId: device.deviceId,
            }
        );

        if ( ! response ) {
            throw new Error(`No device info found for deviceId: ${device.deviceId}`);
        }

        return response as ITpLinkCloudDeviceListItem;
    }

    async makeRequest(
        method: string,
        url: string,
        params: Record<string, any> = {}
    ): Promise<Record<string, any>> {
        const request = {
            method: "POST",
            url: url,
            params: {
                appName: this.appName,
                termID: this.termID,
                appVer: this.appVer,
                ospf: this.ospf,
                netType: this.netType,
                locale: this.locale,
                token: this.token
            },
            headers: {
                "cache-control": "no-cache",
                "User-Agent": this.userAgent,
                "Content-Type": "application/json",
                // Authorization: `Bearer ${this.token}`,
            },
            data: {
                method: method,
                params: params,
            }
        };

        const response = await axios(request);

        if( ! response.data || response.data.error_code !== 0 ){
            throw new Error(`Request failed: ${response.data.error_code} ${response.data.msg}`);
        }

        return response.data.result;
    }
}

export interface ITpLinkCloudConstructorParams {
    token: string;
    termID: string;
    appName: string;
    appVer: string;
    ospf: string;
    netType: string;
    locale: string;
    userAgent: string;
}

export interface ITpLinkCloudProperties {
    termID?: string;
    appName?: string;
    appVer?: string;
    ospf?: string;
    netType?: string;
    locale?: string;
    userAgent?: string;
}

export interface ITpLinkCloudDeviceListItem {
    deviceType: string;
    accountApiUrl: string;
    role: number;
    fwVer: string;
    appServerUrl: string;
    deviceRegion: string;
    deviceId: string;
    deviceName: string;
    deviceHwVer: string;
    alias: string;
    deviceMac: string;
    oemId: string;
    deviceModel: string;
    hwId: string;
    fwId: string;
    isSameRegion: boolean;
    appServerUrlV2: string;
    status: number;
}
