import * as k8s from '@kubernetes/client-node';
import { CertificateStoreName, NamespaceName, WebhookDNSEndpoint, WebhookName } from './Constants.js'
import forge from 'node-forge';
import { logger } from './LoggerWrapper.js';

class WebhookCertData {
    caCert: string;
    caKey: string;
    tlsCert: string;
    tlsKey: string;
}

export class CertificateManager {
    
    // Generate a random serial number for the Certificate
    private static randomHexSerialNumber() {
        return (1001).toString(16) + Math.ceil(Math.random()*100); //Just creates a placeholder hex and randomly increments it with a number between 1 and 100
    }

    private static async GenerateCACertificate(existingKeyPair?: forge.pki.rsa.KeyPair): Promise<forge.pki.Certificate> {
        const currentTime: number = Date.now();
        const caCert = forge.pki.createCertificate();
        const keys = existingKeyPair || forge.pki.rsa.generateKeyPair();
        caCert.serialNumber = CertificateManager.randomHexSerialNumber();
        caCert.publicKey = keys.publicKey;
        caCert.privateKey = keys.privateKey;
        caCert.validity.notBefore = new Date(currentTime - (5 * 60 * 1000)); //5 Mins ago
        caCert.validity.notAfter = new Date(currentTime + (2 * 365 * 24 * 60 * 60 * 1000)); //2 Years from now

        const attributes = [{
            shortName: 'CN',
            value: 'applicationinsights-ca'
        }];
        caCert.setSubject(attributes);
        caCert.setIssuer(attributes);
    
        const extensions = [{
            name: 'basicConstraints',
            cA: true
        },
        {
            name: 'subjectKeyIdentifier',
            keyIdentifier: caCert.generateSubjectKeyIdentifier().getBytes(),
        },
        {
            name: 'keyUsage',
            keyCertSign: true,
            cRLSign: true,
            digitalSignature: true,
            keyEncipherment: true,
        }];

        caCert.setExtensions(extensions);
        caCert.sign(caCert.privateKey,forge.md.sha256.create());

        return caCert;
    }

    private static async GenerateHostCertificate(caCert: forge.pki.Certificate): Promise<forge.pki.Certificate> {
        const currentTime: number = Date.now();
        const host_attributes = [{
            shortName: 'CN',
            value: WebhookDNSEndpoint
        }];
    
        const host_extensions = [{
            name: 'basicConstraints',
            cA: false
        }, 
        {
            name: 'authorityKeyIdentifier',
            keyIdentifier: caCert.generateSubjectKeyIdentifier().getBytes(),
        }, 
        {
            name: 'keyUsage',
            digitalSignature: true,
            keyEncipherment: true
        },
        {
            name: 'extKeyUsage',
            serverAuth: true
        }, 
        {
            name: 'subjectAltName',
            altNames: [{ type: 2, value: WebhookDNSEndpoint }]
        }];

        const newHostCert = forge.pki.createCertificate();
        const hostKeys = forge.pki.rsa.generateKeyPair(4096);

        // Set the attributes for the new Host Certificate
        newHostCert.publicKey = hostKeys.publicKey;
        newHostCert.serialNumber = CertificateManager.randomHexSerialNumber();
        newHostCert.validity.notBefore = new Date(currentTime - (5 * 60 * 1000)); //5 Mins ago
        newHostCert.validity.notAfter = new Date(currentTime + (2 * 365 * 24 * 60 * 60 * 1000)); //2 Years from now
        newHostCert.setSubject(host_attributes);
        newHostCert.setIssuer(caCert.subject.attributes);
        newHostCert.setExtensions(host_extensions);

        // Sign the new Host Certificate using the CA
        newHostCert.sign(caCert.privateKey, forge.md.sha256.create());

        // // Convert to PEM format
        return newHostCert;
    }

    private static async CreateOrUpdateCertificates(currentCACert?: forge.pki.Certificate): Promise<WebhookCertData> {
        try {
            let caCertResult: forge.pki.Certificate = currentCACert;

            if (!caCertResult) {
                caCertResult = await CertificateManager.GenerateCACertificate()
            }

            const hostCertificate = await CertificateManager.GenerateHostCertificate(caCertResult);

            return {
                caCert: forge.pki.certificateToPem(caCertResult),
                caKey: forge.pki.privateKeyToPem(caCertResult.privateKey),
                tlsCert: forge.pki.certificateToPem(hostCertificate),
                tlsKey: forge.pki.privateKeyToPem(hostCertificate.privateKey)
            } as WebhookCertData;
            
        } catch (error) {
            logger.error('Self Signed CA Cert generation failed!');
            logger.error(JSON.stringify(error));
            throw error;
        }
    }

    public static async PatchSecretStore(kubeConfig: k8s.KubeConfig, certificate: WebhookCertData) {
        try {
            const secretsApi = kubeConfig.makeApiClient(k8s.CoreV1Api);
            const secretStore = await secretsApi.readNamespacedSecret(CertificateStoreName, NamespaceName);
            const secretsObj: k8s.V1Secret = secretStore.body;

            secretsObj.data['ca.cert'] = btoa(certificate.caCert);
            secretsObj.data['ca.key'] = btoa(certificate.caKey);
            secretsObj.data['tls.cert'] = btoa(certificate.tlsCert);
            secretsObj.data['tls.key'] = btoa(certificate.tlsKey);

            await secretsApi.patchNamespacedSecret(CertificateStoreName, NamespaceName, secretsObj, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        } catch (error) {
            logger.error('Failed to patch Secret Store!');
            logger.error(JSON.stringify(error));
            throw error;
        }
    }

    public static async GetSecretDetails(kubeConfig: k8s.KubeConfig): Promise<WebhookCertData> {
        try {
            const k8sApi = kubeConfig.makeApiClient(k8s.CoreV1Api);
            const secretStore = await k8sApi.readNamespacedSecret(CertificateStoreName, NamespaceName)
            const secretsObj = secretStore.body;
            if (secretsObj.data) {
                const certificate: WebhookCertData = {
                    caCert: Buffer.from(secretsObj.data['ca.cert'], 'base64').toString('utf-8'),
                    caKey: Buffer.from(secretsObj.data['ca.key'], 'base64').toString('utf-8'),
                    tlsCert: Buffer.from(secretsObj.data['tls.cert'], 'base64').toString('utf-8'),
                    tlsKey: Buffer.from(secretsObj.data['tls.key'], 'base64').toString('utf-8')
                };

                return certificate;
            }
        } catch (error) {
            logger.error(error);
        }
    }

    public static async GetMutatingWebhookCABundle(kubeConfig: k8s.KubeConfig): Promise<string> {
        try {
            const webhookApi: k8s.AdmissionregistrationV1Api = kubeConfig.makeApiClient(k8s.AdmissionregistrationV1Api);
            const mutatingWebhook = await webhookApi.readMutatingWebhookConfiguration(WebhookName);
            const mutatingWebhookObject: k8s.V1MutatingWebhookConfiguration = mutatingWebhook.body;
            if (!mutatingWebhookObject 
                || !mutatingWebhookObject.webhooks 
                || mutatingWebhookObject.webhooks.length !== 1 || !mutatingWebhookObject.webhooks[0].clientConfig)
            {
                throw new Error("MutatingWebhookConfiguration not found or is malformed!");
            }

            return Buffer.from(mutatingWebhookObject.webhooks[0].clientConfig.caBundle, 'base64').toString('utf-8');
        } catch (error) {
            logger.error('Failed to get MutatingWebhookConfiguration!');
            logger.error(JSON.stringify(error));
            throw error;
        }
    }

    public static async PatchMutatingWebhook(kubeConfig: k8s.KubeConfig, certificate: WebhookCertData) {
        try {
            const webhookApi: k8s.AdmissionregistrationV1Api = kubeConfig.makeApiClient(k8s.AdmissionregistrationV1Api);
            const mutatingWebhook = await webhookApi.readMutatingWebhookConfiguration(WebhookName);
            const mutatingWebhookObject: k8s.V1MutatingWebhookConfiguration = mutatingWebhook.body;
            if (!mutatingWebhookObject 
                || !mutatingWebhookObject.webhooks 
                || mutatingWebhookObject.webhooks.length !== 1 || !mutatingWebhookObject.webhooks[0].clientConfig)
            {
                throw new Error("MutatingWebhookConfiguration not found or is malformed!");
            }
            mutatingWebhookObject.webhooks[0].clientConfig.caBundle = btoa(certificate.caCert);
    
            await webhookApi.patchMutatingWebhookConfiguration(WebhookName, mutatingWebhookObject, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        } catch (error) {
            logger.error('Failed to patch MutatingWebhookConfiguration!');
            logger.error(JSON.stringify(error));
            throw error;
        }
    }

    private static isCertificateSignedByCA(pemCertificate: string, pemCACertificate: string): boolean {
        const certificate: forge.pki.Certificate = forge.pki.certificateFromPem(pemCertificate);
        const caCertificate: forge.pki.Certificate = forge.pki.certificateFromPem(pemCACertificate);
        // Verify the signature on the certificate
        return caCertificate.verify(certificate);
    }

    public static async CreateWebhookAndCertificates() {
        const kc = new k8s.KubeConfig();
        kc.loadFromDefault();

        logger.info('Creating certificates...');
        const certificates: WebhookCertData = await CertificateManager.CreateOrUpdateCertificates() as WebhookCertData;
        logger.info('Certificates created successfully');

        CertificateManager.PatchWebhookAndCertificates(kc, certificates);
    }

    public static async ReconcileWebhookAndCertificates() {
        const kc = new k8s.KubeConfig();
        kc.loadFromDefault();
        let certificates: WebhookCertData = null;

        const webhookCertData: WebhookCertData = await CertificateManager.GetSecretDetails(kc);
        const mwhcCaBundle: string = await CertificateManager.GetMutatingWebhookCABundle(kc);

        const matchValidation: boolean = mwhcCaBundle.localeCompare(webhookCertData.caCert) === 0;
        const certSignedByGivenCA: boolean = matchValidation && CertificateManager.isCertificateSignedByCA(webhookCertData.tlsCert, mwhcCaBundle);

        if (!certSignedByGivenCA)
        {
            logger.info('Creating certificates...');
            certificates = await CertificateManager.CreateOrUpdateCertificates() as WebhookCertData;
            logger.info('Certificates created successfully');
            CertificateManager.PatchWebhookAndCertificates(kc, certificates);
            return;
        }

        const timeNow: number = Date.now();
        const dayVal: number = 24 * 60 * 60 * 1000;
        let shouldUpdate = false;
        let cACert: forge.pki.Certificate = null;
        const caPublicCertificate: forge.pki.Certificate = forge.pki.certificateFromPem(webhookCertData.caCert);
        const caKeyPair: forge.pki.rsa.KeyPair = {
            privateKey: forge.pki.privateKeyFromPem(webhookCertData.caKey),
            publicKey: caPublicCertificate.publicKey as forge.pki.rsa.PublicKey
        }

        let daysToExpiry = (caPublicCertificate.validity.notAfter.valueOf() - timeNow)/dayVal;
        if (daysToExpiry < 90) {
            shouldUpdate = true;
            cACert = await CertificateManager.GenerateCACertificate(caKeyPair);
            webhookCertData.caCert = forge.pki.certificateToPem(cACert);
        }

        const hostCertificate: forge.pki.Certificate = forge.pki.certificateFromPem(webhookCertData.tlsCert);
        daysToExpiry = (hostCertificate.validity.notAfter.valueOf() - timeNow)/dayVal;
        if (daysToExpiry < 90) {
            shouldUpdate = true;
            const newHostCert: forge.pki.Certificate = await CertificateManager.GenerateHostCertificate(cACert);
            webhookCertData.tlsCert = forge.pki.certificateToPem(newHostCert);
            webhookCertData.tlsKey = forge.pki.privateKeyToPem(newHostCert.privateKey);
        }

        if (shouldUpdate) {
            CertificateManager.PatchWebhookAndCertificates(kc, webhookCertData);
        }
    }

    private static async PatchWebhookAndCertificates(kc: k8s.KubeConfig, certificates: WebhookCertData) {

        logger.info('Patching Secret Store...');
        await CertificateManager.PatchSecretStore(kc, certificates);
        logger.info('Secret Store patched successfully');

        logger.info('Patching MutatingWebhookConfiguration...');
        await CertificateManager.PatchMutatingWebhook(kc, certificates);
        logger.info('MutatingWebhookConfiguration patched successfully');
    }

}
