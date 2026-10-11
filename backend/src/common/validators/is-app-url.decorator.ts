import {
  registerDecorator,
  ValidationOptions,
  ValidationArguments,
} from 'class-validator';
import { isURL } from 'validator';

/**
 * Remplace @IsUrl() pour toute URL censée provenir du service d'upload de
 * l'application (POST /api/v1/upload/:type) : logo/bannière boutique, avatar,
 * image de catégorie, image de message, image de variante produit, etc.
 *
 * Pourquoi : @IsUrl() de class-validator exige par défaut un nom de domaine
 * avec TLD (option require_tld: true). En développement, STORAGE_DRIVER=local
 * fait renvoyer par le service d'upload des URL de la forme
 * "http://localhost:3001/uploads/shop/xxx.jpg" — "localhost" n'a pas de TLD,
 * donc @IsUrl() les rejetait avec "URL logo invalide" / "URL bannière
 * invalide" alors que le fichier avait bien été envoyé avec succès.
 * En production (domaine réel), le comportement ne change pas : les deux
 * décorateurs acceptent les mêmes URL valides.
 */
export function IsAppUrl(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isAppUrl',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          return (
            typeof value === 'string' &&
            isURL(value, {
              protocols: ['http', 'https'],
              require_protocol: true,
              require_tld: false,
            })
          );
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} doit être une URL valide`;
        },
      },
    });
  };
}
