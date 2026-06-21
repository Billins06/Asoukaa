// import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
// import { Observable } from 'rxjs';
// import { map } from 'rxjs/operators';

// @Injectable()
// export class SanitizeLogsInterceptor implements NestInterceptor {
//   private sensitiveFields = [
//     'password',
//     'passwordHash',
//     'token',
//     'accessToken',
//     'refreshToken',
//     'invitationToken',
//     'paymentDetails',
//     'creditCard',
//     'ssn',
//     'bankAccount',
//   ];

//   intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
//     return next.handle().pipe(
//       map((response) => {
//         this.sanitizeObject(response);
//         return response;
//       }),
//     );
//   }

//   private sanitizeObject(obj: any): void {
//     if (!obj || typeof obj !== 'object') {
//       return;
//     }

//     for (const key in obj) {
//       if (obj.hasOwnProperty(key)) {
//         if (this.sensitiveFields.some(field => key.toLowerCase().includes(field))) {
//           obj[key] = '***REDACTED***';
//         } else if (typeof obj[key] === 'object') {
//           this.sanitizeObject(obj[key]);
//         }
//       }
//     }
//   }
// }


import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';  // ← tap, pas map

@Injectable()
export class SanitizeLogsInterceptor implements NestInterceptor {
  private sensitiveFields = [
    'password', 'passwordHash', 'token', 'accessToken',
    'refreshToken', 'invitationToken', 'paymentDetails',
    'creditCard', 'ssn', 'bankAccount',
  ];

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      tap((response) => {
        // ✅ Clone profond → on sanitise la COPIE pour les logs
        // La vraie réponse HTTP reste intacte
        const sanitized = JSON.parse(JSON.stringify(response ?? {}));
        this.sanitizeObject(sanitized);
        // console.log(sanitized); // ← log ici si nécessaire
      }),
    );
  }

  private sanitizeObject(obj: any): void {
    if (!obj || typeof obj !== 'object') return;
    for (const key in obj) {
      if (Object.prototype.hasOwnProperty.call(obj, key)) {
        if (this.sensitiveFields.some(field => key.toLowerCase().includes(field.toLowerCase()))) {
          obj[key] = '***REDACTED***';
        } else if (typeof obj[key] === 'object') {
          this.sanitizeObject(obj[key]);
        }
      }
    }
  }
}
