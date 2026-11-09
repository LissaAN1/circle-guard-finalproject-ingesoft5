import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet } from 'react-native';
import { useAuth } from '@/context/AuthContext';
import { usePermission } from '@/hooks/usePermission';
import { useGateValidation } from '@/hooks/useGateValidation';

/** Manual, accessible web alternative to camera scanning for authorized gate staff.
 * Calls the real gateway via the same useGateValidation hook as the scanner.
 * Not an alternate backend security boundary: backend RBAC remains a separate concern.
 */
export default function GateValidationScreen() {
  const { token, isLoading } = useAuth();
  const { hasPermission } = usePermission();
  const { validateToken, status, result, reset } = useGateValidation();
  const [qrToken, setQrToken] = useState('');

  if (isLoading) return <Text>LOADING ACCESS CHECK</Text>;
  if (!token || !hasPermission('gate:scan')) {
    return <Text>STAFF ACCESS REQUIRED</Text>;
  }

  const runValidation = async () => {
    if (!qrToken.trim() || status === 'validating') return;
    reset();
    await validateToken(qrToken.trim());
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Gate validation</Text>
      <Text style={styles.help}>Manual QR token entry for staff when the camera is unavailable.</Text>
      <TextInput
        accessibilityLabel="QR token"
        placeholder="Paste QR token"
        autoCapitalize="none"
        autoCorrect={false}
        value={qrToken}
        onChangeText={setQrToken}
        style={styles.input}
      />
      <TouchableOpacity
        accessibilityRole="button"
        accessibilityLabel="Validate access"
        disabled={!qrToken.trim() || status === 'validating'}
        onPress={runValidation}
        style={styles.button}
      >
        <Text style={styles.buttonText}>
          {status === 'validating' ? 'VALIDATING...' : 'VALIDATE ACCESS'}
        </Text>
      </TouchableOpacity>
      {status !== 'idle' && status !== 'validating' && result && (
        <View accessibilityLiveRegion="polite">
          <Text style={[styles.result, { color: result.valid ? '#15803d' : '#b91c1c' }]}>
            {result.valid ? 'ACCESS GRANTED' : 'ACCESS DENIED'}
          </Text>
          <Text>{result.message}</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 24, backgroundColor: '#f8fafc' },
  title: { fontSize: 26, fontWeight: 'bold', marginBottom: 12 },
  help: { marginBottom: 18, color: '#475569' },
  input: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#94a3b8', padding: 12, borderRadius: 8, marginBottom: 16 },
  button: { backgroundColor: '#0e7490', padding: 14, borderRadius: 8, marginBottom: 18 },
  buttonText: { color: '#fff', fontWeight: 'bold' },
  result: { fontSize: 22, fontWeight: 'bold', marginBottom: 8 },
});
