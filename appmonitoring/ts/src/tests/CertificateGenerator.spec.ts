import { CertificateManager, WebhookCertData } from '../CertificateGenerator.js';
import * as k8s from '@kubernetes/client-node';
import exp from 'constants';
import forge from 'node-forge';

describe('CertificateManager', () => {
    let kubeConfig: k8s.KubeConfig;

    beforeEach(() => {
        kubeConfig = new k8s.KubeConfig();
        jest.clearAllMocks();
        jest.resetAllMocks();
        // Set up kubeConfig with necessary configurations
    });

    // describe('GenerateCACertificate', () => {
    //     it('should generate a CA certificate', async () => {
    //         const caCert = await CertificateManager.GenerateCACertificate();
    //         expect(caCert).toBeInstanceOf(forge.pki.Certificate);
    //     });

    //     it('should generate a CA certificate with existing key pair', async () => {
    //         const existingKeyPair = forge.pki.rsa.generateKeyPair(2048);
    //         const caCert = await CertificateManager.GenerateCACertificate(existingKeyPair);
    //         expect(caCert).toBeInstanceOf(forge.pki.Certificate);
    //     });
    // });

    // describe('GenerateHostCertificate', () => {
    //     it('should generate a host certificate', async () => {
    //         const caCert = forge.pki.createCertificate();
    //         const hostCert = await CertificateManager.GenerateHostCertificate(caCert);
    //         expect(hostCert).toBeInstanceOf(forge.pki.Certificate);
    //     });
    // });

    // Add more test cases for other methods in CertificateManager

    describe('CreateWebhookAndCertificates', () => {
        it('should create and patch webhook and certificates', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            const createOrUpdateCertificates = jest.spyOn(CertificateManager as any, 'CreateOrUpdateCertificates').mockReturnValue({
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsKey: 'mockTLSKey',
                tlsCert: 'mockTLSCert',
            } as WebhookCertData);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockResolvedValue(null);

            const operationId = 'operationId';
            await CertificateManager.CreateWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            expect(createOrUpdateCertificates).toHaveBeenCalledWith(operationId);
            expect(patchWebhookAndCertificates).toHaveBeenCalledWith(operationId, mockKubeConfig, {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsKey: 'mockTLSKey',
                tlsCert: 'mockTLSCert',
            } as WebhookCertData, mockClusterArmId, mockClusterArmRegion);
        });
    });

    describe('ReconcileWebhookAndCertificates', () => {
        it('should reconcile webhook and certificates - happy path', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            const secretObj: WebhookCertData = (CertificateManager as any).CreateOrUpdateCertificates('test-operationId');
            jest.spyOn(CertificateManager as any, 'GetSecretDetails').mockResolvedValue(secretObj);
            const getMutatingWebhookCABundle = jest.spyOn(CertificateManager as any, 'GetMutatingWebhookCABundle').mockResolvedValue(secretObj.caCert);
            jest.spyOn(CertificateManager as any, 'isCertificateSignedByCA').mockReturnValue(true);
            const isValidCertificate = jest.spyOn(CertificateManager as any, 'IsValidCertificate').mockReturnValue(true);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockResolvedValue(null);
            const restartWebhookReplicaset = jest.spyOn(CertificateManager as any, 'RestartWebhookReplicaset').mockResolvedValue(null);

            const operationId = 'operationId';
            await CertificateManager.ReconcileWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            expect(isValidCertificate).toHaveBeenCalledWith(operationId, secretObj.caCert, secretObj, mockClusterArmId, mockClusterArmRegion);
            expect(getMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(patchWebhookAndCertificates).not.toBeCalled();
            expect(restartWebhookReplicaset).not.toBeCalled();
        });
    });

    describe('PatchMutatingWebhook', () => {
        it('should patch mutating webhook', async () => {
            // Arrange
            const operationId = 'operationId';
            const mockKubeConfig = new k8s.KubeConfig();
            const mockCertificate: WebhookCertData = {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsCert: 'mockTLSCert',
                tlsKey: 'mockTLSKey',
            };
            const clusterArmId = 'clusterArmId';
            const clusterArmRegion = 'clusterArmRegion';
            const mutatingwebhookobject = {
                response: null,
                body: {
                    webhooks: [
                        {
                            name: 'app-monitoring-webhook',
                            clientConfig: {
                                caBundle: ''
                            }
                        } as k8s.V1MutatingWebhook
                    ]
                }
            };
            const readMutatingWebhookConfiguration  = jest.spyOn(k8s.AdmissionregistrationV1Api.prototype, 'readMutatingWebhookConfiguration').mockResolvedValue(mutatingwebhookobject);
            const mutatingwebhookobjectBodyCopy: k8s.V1MutatingWebhookConfiguration = JSON.parse(JSON.stringify(mutatingwebhookobject.body));
            const patchMutatingWebhookConfiguration  = jest.spyOn(k8s.AdmissionregistrationV1Api.prototype, 'patchMutatingWebhookConfiguration').mockResolvedValue(null);
            mutatingwebhookobjectBodyCopy.webhooks[0].clientConfig.caBundle = Buffer.from(mockCertificate.caCert, 'utf-8').toString('base64');
            const mockApiClient = jest.spyOn(k8s.KubeConfig.prototype, 'makeApiClient').mockReturnValue(new k8s.AdmissionregistrationV1Api());

            // Mock the methods in CertificateManager
            jest.spyOn(CertificateManager, 'PatchMutatingWebhook');
            
            // Act
            await CertificateManager.PatchMutatingWebhook(operationId, mockKubeConfig, mockCertificate);
            mutatingwebhookobject.body.webhooks[0].clientConfig.caBundle = Buffer.from(mockCertificate.caCert, 'utf-8').toString('base64');

            // Assert
            expect(readMutatingWebhookConfiguration).toHaveBeenCalledWith('app-monitoring-webhook');
            expect(patchMutatingWebhookConfiguration).toHaveBeenCalledWith('app-monitoring-webhook', mutatingwebhookobjectBodyCopy, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        });
    });

    describe('PatchSecretStore', () => {
        it('should patch secret store', async () => {
            // Arrange
            const operationId = 'operationId';
            const mockKubeConfig = new k8s.KubeConfig();
            const mockCertificate: WebhookCertData = {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsCert: 'mockTLSCert',
                tlsKey: 'mockTLSKey',
            };
            const clusterArmId = 'clusterArmId';
            const clusterArmRegion = 'clusterArmRegion';
            const secretObject = {
                response: null,
                body: {
                    data: {
                        'ca.cert': '',
                        'ca.key': '',
                        'tls.cert': '',
                        'tls.key': ''
                    }
                }
            };
            const readNamespacedSecret = jest.spyOn(k8s.CoreV1Api.prototype, 'readNamespacedSecret').mockResolvedValue(secretObject);
            const patchNamespacedSecret = jest.spyOn(k8s.CoreV1Api.prototype, 'patchNamespacedSecret').mockResolvedValue(null);
            const mockApiClient = jest.spyOn(k8s.KubeConfig.prototype, 'makeApiClient').mockReturnValue(new k8s.CoreV1Api());

            // Mock the methods in CertificateManager
            jest.spyOn(CertificateManager, 'PatchSecretStore');
            
            // Act
            await CertificateManager.PatchSecretStore(operationId, mockKubeConfig, mockCertificate);

            // Assert
            expect(readNamespacedSecret).toHaveBeenCalledWith('app-monitoring-webhook-cert', 'kube-system');
            expect(patchNamespacedSecret).toHaveBeenCalledWith('app-monitoring-webhook-cert', 'kube-system', {
                data: {
                    'ca.cert': Buffer.from(mockCertificate.caCert, 'utf-8').toString('base64'),
                    'ca.key': Buffer.from(mockCertificate.caKey, 'utf-8').toString('base64'),
                    'tls.cert': Buffer.from(mockCertificate.tlsCert, 'utf-8').toString('base64'),
                    'tls.key': Buffer.from(mockCertificate.tlsKey, 'utf-8').toString('base64')
                }
            }, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        });
    });

    describe('CreateWebhookAndCertificates', () => {
        it('should create webhook and certificates', async () => {
            const operationId = 'operationId';
            const clusterArmId = 'clusterArmId';
            const clusterArmRegion = 'clusterArmRegion';



            // Mock necessary dependencies and perform the test

            // Assert the expected behavior
        });
    });

    describe('GenerateCACertificate', () => {
        it('should generate a CA certificate', async () => {
            jest.spyOn(Date, 'now').mockReturnValue(0);
            const caCert: forge.pki.Certificate = (CertificateManager as any).GenerateCACertificate();
            expect(caCert.subject.attributes[0].value).toStrictEqual('applicationinsights-ca');
            expect(caCert.subject.attributes[0].shortName).toStrictEqual('CN');
            expect(caCert.extensions[0].name).toStrictEqual('basicConstraints');
            expect(caCert.extensions[0].cA).toBeTruthy();
            expect(caCert.extensions[1].name).toStrictEqual('subjectKeyIdentifier');
            expect(caCert.extensions[2].name).toStrictEqual('keyUsage');
            expect(caCert.validity.notBefore).toStrictEqual(new Date(0 - (5 * 60 * 1000)));
            expect(caCert.validity.notAfter).toStrictEqual(new Date(2 * 365 * 24 * 60 * 60 * 1000));
        });
    });

    describe('GenerateHostCertificate', () => { 
        it('should generate a host certificate', async () => {
            jest.spyOn(Date, 'now').mockReturnValue(0);
            const caCert = (CertificateManager as any).GenerateCACertificate();
            const hostCert: forge.pki.Certificate = (CertificateManager as any).GenerateHostCertificate(caCert);
            expect(hostCert.subject.attributes[0].value).toStrictEqual('app-monitoring-webhook-service.kube-system.svc');
            expect(hostCert.subject.attributes[0].shortName).toStrictEqual('CN');
            expect(hostCert.extensions[0].name).toStrictEqual('basicConstraints');
            expect(hostCert.extensions[0].cA).toBeFalsy();
            expect(hostCert.extensions[1].name).toStrictEqual('authorityKeyIdentifier');
            expect(hostCert.extensions[2].name).toStrictEqual('keyUsage');
            expect(hostCert.extensions[3].name).toStrictEqual('extKeyUsage');
            expect(hostCert.extensions[4].name).toStrictEqual('subjectAltName');
            expect(hostCert.validity.notBefore).toStrictEqual(new Date(0 - (5 * 60 * 1000)));
            expect(hostCert.validity.notAfter).toStrictEqual(new Date(2 * 365 * 24 * 60 * 60 * 1000));
            expect(caCert.verify(hostCert)).toBeTruthy();
        });
    });

    // describe('ReconcileWebhookAndCertificates', () => {
    //     it('should reconcile webhook and certificates', async () => {
    //         // Arrange
    //         const operationId = 'operationId';
    //         const clusterArmId = 'clusterArmId';
    //         const clusterArmRegion = 'clusterArmRegion';

    //         // Mock necessary dependencies
    //         const mockKubeConfig = new k8s.KubeConfig();
    //         const mockCertificate: WebhookCertData = {
    //             caCert: 'mockCACert',
    //             caKey: 'mockCAKey',
    //             tlsCert: 'mockTLSCert',
    //             tlsKey: 'mockTLSKey'
    //         };
    //         const mockReconciledCertData: WebhookCertData = {
    //             caCert: 'reconciledCACert',
    //             caKey: 'reconciledCAKey',
    //             tlsCert: 'reconciledTLSCert',
    //             tlsKey: 'reconciledTLSKey'
    //         };
    //         const mockRestartedReplicaset = jest.fn();
    //         const mockPatchWebhookAndCertificates = jest.fn().mockResolvedValue(mockReconciledCertData);
    //         const mockIsValidateCertificate = jest.fn().mockReturnValue(true);
    //         const mockGetMutatingWebhookCABundle = jest.fn().mockResolvedValue('mockCABundle');

    //         // Mock the methods in CertificateManager
    //         jest.spyOn(CertificateManager, 'PatchMutatingWebhook').mockImplementation(mockPatchWebhookAndCertificates);
    //         jest.spyOn(CertificateManager, 'PatchSecretStore').mockImplementation(mockIsValidateCertificate);
    //         jest.spyOn(CertificateManager, 'GetMutatingWebhookCABundle').mockImplementation(mockGetMutatingWebhookCABundle);

    //         // Act
    //         await CertificateManager.ReconcileWebhookAndCertificates(operationId, clusterArmId, clusterArmRegion);

    //         // Assert
    //         expect(mockPatchWebhookAndCertificates).toHaveBeenCalledWith(operationId, mockKubeConfig, mockCertificate, clusterArmId, clusterArmRegion);
    //         expect(mockIsValidateCertificate).toHaveBeenCalledWith(operationId, 'mockCABundle', mockReconciledCertData, clusterArmId, clusterArmRegion);
    //         expect(mockRestartedReplicaset).toHaveBeenCalledWith(operationId, mockKubeConfig, clusterArmId, clusterArmRegion);
    //         expect(mockGetMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
    //     });
    // });

    // Add more test cases for other methods in CertificateManager
});

