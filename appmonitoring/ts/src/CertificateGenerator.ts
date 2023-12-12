import * as k8s from '@kubernetes/client-node';
import { CertificateStoreName, NamespaceName, WebhookDNSEndpoint, WebhookName } from './Constants.js'
import forge from 'node-forge';
import { logger, RequestMetadata } from './LoggerWrapper.js';

export class WebhookCertData {
    caCert: string;
    caKey: string;
    tlsCert: string;
    tlsKey: string;
}

export class CertificateManager {
    
    private static requestMetadata = new RequestMetadata(null, null);

    // Generate a random serial number for the Certificate
    private static randomHexSerialNumber() {
        return (1001).toString(16) + Math.ceil(Math.random()*100); //Just creates a placeholder hex and randomly increments it with a number between 1 and 100
    }

    private static GenerateCACertificate(existingKeyPair?: forge.pki.rsa.KeyPair): forge.pki.Certificate {
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

    private static GenerateHostCertificate(caCert: forge.pki.Certificate): forge.pki.Certificate {
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
        newHostCert.privateKey = hostKeys.privateKey;
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

    private static CreateOrUpdateCertificates(operationId: string, currentCACert?: forge.pki.Certificate): WebhookCertData {
        try {
            let caCertResult: forge.pki.Certificate = currentCACert;

            if (!caCertResult) {
                caCertResult = CertificateManager.GenerateCACertificate()
            }

            const hostCertificate = CertificateManager.GenerateHostCertificate(caCertResult);

            return {
                caCert: forge.pki.certificateToPem(caCertResult),
                caKey: forge.pki.privateKeyToPem(caCertResult.privateKey),
                tlsCert: forge.pki.certificateToPem(hostCertificate),
                tlsKey: forge.pki.privateKeyToPem(hostCertificate.privateKey)
            } as WebhookCertData;
            
        } catch (error) {
            logger.error('Self Signed CA Cert generation failed!', operationId, this.requestMetadata);
            logger.error(JSON.stringify(error), operationId, this.requestMetadata);
            throw error;
        }
    }

    public static async PatchSecretStore(operationId: string, kubeConfig: k8s.KubeConfig, certificate: WebhookCertData) {
        try {
            const secretsApi = kubeConfig.makeApiClient(k8s.CoreV1Api);
            const secretStore = await secretsApi.readNamespacedSecret(CertificateStoreName, NamespaceName);
            const secretsObj: k8s.V1Secret = secretStore.body;

            secretsObj.data['ca.cert'] = Buffer.from(certificate.caCert, 'utf-8').toString('base64');
            secretsObj.data['ca.key'] = Buffer.from(certificate.caKey, 'utf-8').toString('base64');
            secretsObj.data['tls.cert'] = Buffer.from(certificate.tlsCert, 'utf-8').toString('base64');
            secretsObj.data['tls.key'] = Buffer.from(certificate.tlsKey, 'utf-8').toString('base64');

            await secretsApi.patchNamespacedSecret(CertificateStoreName, NamespaceName, secretsObj, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        } catch (error) {
            logger.error('Failed to patch Secret Store!', operationId, this.requestMetadata);
            logger.error(JSON.stringify(error), operationId, this.requestMetadata);
            throw error;
        }
    }

    public static async GetSecretDetails(operationId: string, kubeConfig: k8s.KubeConfig): Promise<WebhookCertData> {
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
            logger.error(error, operationId, this.requestMetadata);
        }
    }

    public static async GetMutatingWebhookCABundle(operationId: string, kubeConfig: k8s.KubeConfig): Promise<string> {
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
            logger.error('Failed to get MutatingWebhookConfiguration!', operationId, this.requestMetadata);
            logger.error(JSON.stringify(error), operationId, this.requestMetadata);
            throw error;
        }
    }

    public static async PatchMutatingWebhook(operationId: string, kubeConfig: k8s.KubeConfig, certificate: WebhookCertData) {
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
            mutatingWebhookObject.webhooks[0].clientConfig.caBundle = Buffer.from(certificate.caCert, 'utf-8').toString('base64');
            await webhookApi.patchMutatingWebhookConfiguration(WebhookName, mutatingWebhookObject, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        } catch (error) {
            logger.error('Failed to patch MutatingWebhookConfiguration!', operationId, this.requestMetadata);
            logger.error(JSON.stringify(error), operationId, this.requestMetadata);
            throw error;
        }
    }

    private static isCertificateSignedByCA(pemCertificate: string, pemCACertificate: string): boolean {
        if (!pemCertificate || !pemCACertificate) {
            return false;
        }

        const certificate: forge.pki.Certificate = forge.pki.certificateFromPem(pemCertificate);
        const caCertificate: forge.pki.Certificate = forge.pki.certificateFromPem(pemCACertificate);
        // Verify the signature on the certificate
        return caCertificate.verify(certificate);
    }

    public static async CreateWebhookAndCertificates(operationId: string, clusterArmId: string, clusterArmRegion: string) {
        const kc = new k8s.KubeConfig();
        kc.loadFromDefault();

        logger.info('Creating certificates...', operationId, this.requestMetadata);
        logger.SendEvent("CertificateCreating", operationId, null, clusterArmId, clusterArmRegion);
        const certificates: WebhookCertData = CertificateManager.CreateOrUpdateCertificates(operationId) as WebhookCertData;
        logger.info('Certificates created successfully', operationId, this.requestMetadata);
        logger.SendEvent("CertificateCreated", operationId, null, clusterArmId, clusterArmRegion);

        await CertificateManager.PatchWebhookAndCertificates(operationId, kc, certificates, clusterArmId, clusterArmRegion);
    }

    public static async ReconcileWebhookAndCertificates(operationId: string, clusterArmId: string, clusterArmRegion: string) {
        const kc = new k8s.KubeConfig();
        kc.loadFromDefault();
        let certificates: WebhookCertData = null;
        let webhookCertData: WebhookCertData = null;
        let mwhcCaBundle: string = null;

        try {
            webhookCertData = await CertificateManager.GetSecretDetails(operationId, kc);
            mwhcCaBundle = await CertificateManager.GetMutatingWebhookCABundle(operationId, kc);
            if (CertificateManager.IsValidCertificate(operationId, mwhcCaBundle, webhookCertData, clusterArmId, clusterArmRegion)) {
                logger.info('Certificates are valid, continue validation...', operationId, this.requestMetadata);
            } else {
                logger.info('Certificates are not valid, reconciliation not needed at this time...', operationId, this.requestMetadata);
                logger.SendEvent("CertificateValidationFailed", operationId, null, clusterArmId, clusterArmRegion, true);
                return;
            }
        } catch (error) {
            logger.error('Error occured while trying to get Secret Store or MutatingWebhookConfiguration!', operationId, this.requestMetadata);
            logger.error(JSON.stringify(error), operationId, this.requestMetadata);
        }

        const matchValidation: boolean = mwhcCaBundle && webhookCertData && mwhcCaBundle.localeCompare(webhookCertData.caCert) === 0;
        const certSignedByGivenCA: boolean = matchValidation && CertificateManager.isCertificateSignedByCA(webhookCertData.tlsCert, mwhcCaBundle);

        if (!certSignedByGivenCA)
        {
            logger.info('Creating certificates...', operationId, this.requestMetadata);
            logger.SendEvent("CertificateCreating", operationId, null, clusterArmId, clusterArmRegion);
            certificates = CertificateManager.CreateOrUpdateCertificates(operationId) as WebhookCertData;
            logger.info('Certificates created successfully', operationId, this.requestMetadata);
            logger.SendEvent("CertificateCreated", operationId, null, clusterArmId, clusterArmRegion);
            await CertificateManager.PatchWebhookAndCertificates(operationId, kc, certificates, clusterArmId, clusterArmRegion);
            await CertificateManager.RestartWebhookReplicaset(operationId, kc, clusterArmId, clusterArmRegion);
            return;
        }

        const timeNow: number = Date.now();
        const dayVal: number = 24 * 60 * 60 * 1000;
        let shouldUpdate = false;
        let shouldRestartReplicaset = false;
        let cACert: forge.pki.Certificate = null;
        const caPublicCertificate: forge.pki.Certificate = forge.pki.certificateFromPem(webhookCertData.caCert);
        const caKeyPair: forge.pki.rsa.KeyPair = {
            privateKey: forge.pki.privateKeyFromPem(webhookCertData.caKey),
            publicKey: caPublicCertificate.publicKey as forge.pki.rsa.PublicKey
        }

        // Check if CA Cert is relativekly close to expiration
        let daysToExpiry = (caPublicCertificate.validity.notAfter.valueOf() - timeNow)/dayVal;
        if (daysToExpiry < 90) {
            shouldUpdate = true;
            cACert = CertificateManager.GenerateCACertificate(caKeyPair);
            webhookCertData.caCert = forge.pki.certificateToPem(cACert);
        }

        // Check if Host Cert is relatively close to expiration
        const hostCertificate: forge.pki.Certificate = forge.pki.certificateFromPem(webhookCertData.tlsCert);
        daysToExpiry = (hostCertificate.validity.notAfter.valueOf() - timeNow)/dayVal;
        if (daysToExpiry < 90) {
            shouldUpdate = true;
            shouldRestartReplicaset = true;
            const newHostCert: forge.pki.Certificate = CertificateManager.GenerateHostCertificate(cACert);
            webhookCertData.tlsCert = forge.pki.certificateToPem(newHostCert);
            webhookCertData.tlsKey = forge.pki.privateKeyToPem(newHostCert.privateKey);
        }

        if (shouldUpdate) {
            await CertificateManager.PatchWebhookAndCertificates(operationId, kc, webhookCertData, clusterArmId, clusterArmRegion);
            if (shouldRestartReplicaset) {
                await CertificateManager.RestartWebhookReplicaset(operationId, kc, clusterArmId, clusterArmRegion);
            }
        }
        else {
            logger.info('Nothing to do. All is good. Ending this run...', operationId, this.requestMetadata);
        }
    }

    private static IsValidCertificate(operationId: string, mwhcCaBundle: string, webhookCertData: WebhookCertData, clusterArmId: string, clusterArmRegion: string): boolean {
        try {
            forge.pki.certificateFromPem(mwhcCaBundle);
            forge.pki.certificateFromPem(webhookCertData.caCert);
            forge.pki.certificateFromPem(webhookCertData.tlsCert);
            forge.pki.privateKeyFromPem(webhookCertData.tlsKey);
            return true;
        } catch (error) {
            logger.error('Error occured while trying to validate certificates!', operationId, this.requestMetadata);
            logger.error(JSON.stringify(error), operationId, this.requestMetadata);
            logger.SendEvent("CertificateValidationFailed", operationId, null, clusterArmId, clusterArmRegion, true, error);
            return false;
        }
    }

    private static async RestartWebhookReplicaset(operationId: string, kc: k8s.KubeConfig, clusterArmId: string, clusterArmRegion: string) {
        kc.loadFromDefault();

        const k8sApi = kc.makeApiClient(k8s.AppsV1Api);
        const selector = "app=app-monitoring-webhook"
        let name = null;

        try {
            const replicaSets: k8s.V1ReplicaSetList = (await k8sApi.listNamespacedReplicaSet(NamespaceName)).body;

            const matchingReplicaSets: k8s.V1ReplicaSet[] = replicaSets.items.filter(rs => 
                rs.spec.selector.matchLabels.app === selector
            );

            const replicaSet: k8s.V1ReplicaSet = matchingReplicaSets[0];
            const annotations = replicaSet.spec.template.metadata.annotations || {};
            annotations['kubectl.kubernetes.io/restartedAt'] = new Date().toISOString();
            replicaSet.spec.template.metadata.annotations = annotations;
            name = replicaSet.metadata.name;

            logger.info(`Restarting ReplicaSet ${name}...`, operationId, this.requestMetadata);
            logger.SendEvent("CertificateRestartingReplicaSet", operationId, null, clusterArmId, clusterArmRegion);
            await k8sApi.replaceNamespacedReplicaSet(name, NamespaceName, replicaSet);
            console.log(`Successfully restarted ReplicaSet ${name}`);
            logger.SendEvent("CertificateRestartedReplicaSet", operationId, null, clusterArmId, clusterArmRegion);

        } catch (err) {
            logger.error(`Failed to get ReplicaSet ${name}: ${err}`, operationId, this.requestMetadata);
            logger.SendEvent("CertificateRestartFailedReplicaSet", operationId, null, clusterArmId, clusterArmRegion, true, err);
            throw err;
        }
    }

    private static async PatchWebhookAndCertificates(operationId: string, kc: k8s.KubeConfig, certificates: WebhookCertData, clusterArmId: string, clusterArmRegion: string) {
        logger.info('Patching Secret Store...', operationId, this.requestMetadata);
        logger.SendEvent("CertificatePatchingSecretStore", operationId, null, clusterArmId, clusterArmRegion);
        await CertificateManager.PatchSecretStore(operationId, kc, certificates);
        logger.info('Secret Store patched successfully', operationId, this.requestMetadata);

        logger.info('Patching MutatingWebhookConfiguration...', operationId, this.requestMetadata);
        logger.SendEvent("CertificatePatchingMWHC", operationId, null, clusterArmId, clusterArmRegion);
        await CertificateManager.PatchMutatingWebhook(operationId, kc, certificates);
        logger.info('MutatingWebhookConfiguration patched successfully', operationId, this.requestMetadata);
        logger.SendEvent("CertificatePatchedMWHC", operationId, null, clusterArmId, clusterArmRegion);
    }

}
