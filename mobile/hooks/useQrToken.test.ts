import { renderHook, act } from '@testing-library/react-native';
import axios from 'axios';
import { useQrToken } from './useQrToken';

jest.mock('axios');
const mockedGet = axios.get as jest.Mock;

// Lets the resolved axios promise run its continuation inside act().
const flush = () => act(async () => {});

describe('useQrToken', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    mockedGet.mockReset();
    mockedGet.mockResolvedValue({ data: { qrToken: 'qr-1', expiresIn: '60' } });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  test('fetches a token and starts a 60s timer when both ids are present', async () => {
    const { result } = renderHook(() => useQrToken('test-id', 'jwt'));
    await flush();

    expect(mockedGet).toHaveBeenCalledTimes(1);
    expect(mockedGet.mock.calls[0][1].headers.Authorization).toBe('Bearer jwt');
    expect(result.current.token).toBe('qr-1');
    expect(result.current.timeLeft).toBe(60);
  });

  test('does nothing without an anonymous id or an auth token', async () => {
    const { result } = renderHook(() => useQrToken(null, 'jwt'));
    renderHook(() => useQrToken('test-id', null));
    await flush();

    expect(mockedGet).not.toHaveBeenCalled();
    expect(result.current.token).toBeNull();
  });

  test('decrements the timer every second', async () => {
    const { result } = renderHook(() => useQrToken('test-id', 'jwt'));
    await flush();

    act(() => {
      jest.advanceTimersByTime(1000);
    });

    expect(result.current.timeLeft).toBe(59);
  });

  test('uses the lifetime reported by the server', async () => {
    mockedGet.mockResolvedValue({ data: { qrToken: 'qr-short', expiresIn: '30' } });
    const { result } = renderHook(() => useQrToken('test-id', 'jwt'));
    await flush();

    expect(result.current.timeLeft).toBe(30);
  });

  test('rotates the token when the timer reaches 0', async () => {
    mockedGet
      .mockResolvedValueOnce({ data: { qrToken: 'qr-1', expiresIn: '5' } })
      .mockResolvedValueOnce({ data: { qrToken: 'qr-2', expiresIn: '5' } });
    const { result } = renderHook(() => useQrToken('test-id', 'jwt'));
    await flush();
    expect(result.current.token).toBe('qr-1');

    act(() => {
      jest.advanceTimersByTime(5000);
    });
    await flush();

    expect(mockedGet).toHaveBeenCalledTimes(2);
    expect(result.current.token).toBe('qr-2');
  });

  test('keeps the last token when a refresh fails', async () => {
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    mockedGet
      .mockResolvedValueOnce({ data: { qrToken: 'qr-1', expiresIn: '2' } })
      .mockRejectedValueOnce(new Error('network'));
    const { result } = renderHook(() => useQrToken('test-id', 'jwt'));
    await flush();

    act(() => {
      jest.advanceTimersByTime(2000);
    });
    await flush();

    expect(result.current.token).toBe('qr-1');
    expect(error).toHaveBeenCalled();
    error.mockRestore();
  });
});
