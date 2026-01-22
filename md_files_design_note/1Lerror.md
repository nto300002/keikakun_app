Failed to compile.
./hooks/usePushNotification.ts:159:9
Type error: Type 'Uint8Array<ArrayBufferLike>' is not assignable to type 'string | BufferSource | null | undefined'.
  Type 'Uint8Array<ArrayBufferLike>' is not assignable to type 'ArrayBufferView<ArrayBuffer>'.
    Types of property 'buffer' are incompatible.
      Type 'ArrayBufferLike' is not assignable to type 'ArrayBuffer'.
        Type 'SharedArrayBuffer' is missing the following properties from type 'ArrayBuffer': resizable, resize, detached, transfer, transferToFixedLength
  157 |       const subscription = await registration.pushManager.subscribe({
  158 |         userVisibleOnly: true,
> 159 |         applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
      |         ^
  160 |       });
  161 |
  162 |       await http.post<void>(